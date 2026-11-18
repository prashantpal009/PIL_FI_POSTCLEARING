CLASS zcl_http_invoice_clearing DEFINITION
  PUBLIC
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_http_service_extension .
    TYPES: BEGIN OF ty_invoice_details,
             db_key                     TYPE zvendor_payment-db_key,
             company_code               TYPE zvendor_payment-company_code,
             posting_date               TYPE zvendor_payment-posting_date,
             supplier                   TYPE zvendor_payment-supplier,
             journal_entry              TYPE zvendor_payment-journal_entry,
             journal_entry_type         TYPE zvendor_payment-journal_entry_type,
             gl_account                 TYPE zvendor_payment-gl_account,
             amount_proposal            TYPE zvendor_payment-amount_proposal,
             invoice_value              TYPE zvendor_payment-invoice_value,
             invoice_reference          TYPE zvendor_payment-invoice_reference,
             originalreference_document TYPE zvendor_payment-originalreference_document,
             fiscal_year                TYPE zvendor_payment-fiscal_year,
             profit_center              TYPE zvendor_payment-profit_center,
             currency                   TYPE zvendor_payment-currency,
             house_bank                 TYPE zvendor_payment-house_bank,
             house_bank_account         TYPE zvendor_payment-house_bank_account,
             accounting_document_item   TYPE zfi_vendoropenreport-AccountingDocumentItem,
             invoice_date               TYPE zfi_vendoropenreport-InvoiceDate,
             business_place             TYPE zfi_vendoropenreport-BusinessPlace,
             utrnumber                  TYPE zvendor_payment-utrnumber,
             transactionid              TYPE zvendor_payment-transactionid,
             id_no                      TYPE zvendor_payment-id_no,
             post_status                TYPE zvendor_payment-post_status,
           END OF ty_invoice_details.

    TYPES: tt_invoice_details TYPE TABLE OF ty_invoice_details
                     WITH EMPTY KEY.

    TYPES: BEGIN OF ty_item,
             dbkey        TYPE string,
             journalentry TYPE string,
             IdNo         TYPE string,
           END OF ty_item,
           ty_items TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             items TYPE ty_items,
           END OF ty_payload.

    CLASS-METHODS postData
      IMPORTING
        request        TYPE REF TO if_web_http_request
      RETURNING
        VALUE(message) TYPE string.

    CLASS-METHODS postInvoiceData
      IMPORTING
        wa_data        TYPE ty_invoice_details
        c_id           TYPE string
        lv_inv_ref_doc TYPE string
      RETURNING
        VALUE(message) TYPE string.

    CLASS-METHODS
      api_call
        IMPORTING final_xml TYPE string
        RAISING
                  cx_http_dest_provider_error
                  cx_web_http_client_error
                  cx_web_message_error.


  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_HTTP_INVOICE_CLEARING IMPLEMENTATION.


  METHOD if_http_service_extension~handle_request.
    CASE request->get_method( ).
      WHEN CONV string( if_web_http_client=>post ).
        DATA(lv_message) = postData( request ).
        response->set_text( lv_message ).
        IF lv_message CS 'Error' OR lv_message CS 'error' OR lv_message CS 'No items'.
          response->set_status( i_code = 400 i_reason = lv_message ).
        ELSE.
          response->set_status( i_code = 200 i_reason = 'OK' ).
        ENDIF.
      WHEN OTHERS.
        response->set_status( i_code = 405 i_reason = 'Method Not Allowed' ).
    ENDCASE.
  ENDMETHOD.


  METHOD postdata.

    DATA: ls_payload       TYPE ty_payload,
          lv_json          TYPE string,
          lv_messages      TYPE string,
          lv_success_count TYPE i,
          lv_fail_count    TYPE i,
          invoicedetails   TYPE ty_invoice_details,
          lv_db_key        TYPE zvendor_payment-db_key,
          lv_journal       TYPE belnr_d,
          lv_posting_id    TYPE string,
          lv_doc           TYPE string,
          lv_inv_ref_doc   TYPE string,
          lv_result        TYPE string.

    TRY.

        lv_json = request->get_text( ).

        /ui2/cl_json=>deserialize(
          EXPORTING json = lv_json
          CHANGING  data = ls_payload ).

        IF ls_payload-items IS INITIAL.
          message = '{"error":"No items provided"}'.
          RETURN.
        ENDIF.

        DATA: lv_je_alpha TYPE belnr_d.

        LOOP AT ls_payload-items INTO DATA(wa).

          CLEAR: invoicedetails, lv_doc, lv_inv_ref_doc, lv_result.

            lv_je_alpha = |{ wa-journalentry ALPHA = IN }|.

          SELECT SINGLE FROM zvendor_payment AS a
            INNER JOIN zfi_vendoropenreport AS b
              ON  a~journal_entry      = b~journalEntry
              AND a~fiscal_year        = b~FiscalYear
              AND a~company_code       = b~CompanyCode
              AND a~journal_entry_type = b~JournalEntryType
            FIELDS
              a~db_key,
              a~company_code,
              a~posting_date,
              a~supplier,
              a~journal_entry,
              a~journal_entry_type,
              a~gl_account,
              a~amount_proposal,
              a~invoice_value,
              a~invoice_reference,
              a~originalreference_document,
              a~fiscal_year,
              a~profit_center,
              a~currency,
              a~house_bank,
              a~house_bank_account,
              b~AccountingDocumentItem,
              b~InvoiceDate,
              b~BusinessPlace,
              a~utrnumber,
              a~transactionid,
              a~id_no,
              a~post_status
            WHERE  a~id_no = @wa-IdNo
            and a~journal_entry = @lv_je_alpha
              AND a~post_status IS NOT INITIAL
            INTO @invoicedetails.

          IF sy-subrc <> 0.
            lv_fail_count = lv_fail_count + 1.
            lv_messages = lv_messages && |JournalEntry { lv_je_alpha }: Record not found or already posted. |.
            CONTINUE.
          ENDIF.

          TRY.
              DATA(cid) = to_upper( cl_uuid_factory=>create_system_uuid( )->create_uuid_x16( ) ).
            CATCH cx_uuid_error.
              ASSERT 1 = 0.
          ENDTRY.
          lv_doc         = |{ invoicedetails-journal_entry ALPHA = OUT }|.
          lv_inv_ref_doc = |{ lv_doc }{ invoicedetails-fiscal_year }{ invoicedetails-accounting_document_item }|.

          lv_result = postInvoiceData(
            wa_data        = invoicedetails
            c_id           = cid
            lv_inv_ref_doc = lv_inv_ref_doc ).

          IF lv_result CS 'Successfully'.
            lv_success_count = lv_success_count + 1.
          ELSE.
            lv_fail_count = lv_fail_count + 1.
          ENDIF.

          lv_messages = lv_messages && |JournalEntry { wa-journalentry }: { lv_result } |.

        ENDLOOP.

        message = |Processed: { lv_success_count } succeeded, { lv_fail_count } failed. { lv_messages }|.

      CATCH cx_sy_open_sql_db INTO DATA(lx_sql).
        message = |SQL Error: { lx_sql->get_text( ) }|.

      CATCH cx_root INTO DATA(lx_root).
        message = |General Error: { lx_root->get_text( ) }|.

    ENDTRY.


  ENDMETHOD.


  METHOD postinvoicedata.
    DATA: lt_je_deep TYPE TABLE FOR ACTION IMPORT i_journalentrytp~post,
          document   TYPE string.
    DATA: lv_today TYPE d.
    lv_today = cl_abap_context_info=>get_system_date( ).
    DATA(lv_uname) = cl_abap_context_info=>get_user_technical_name( ).

    DATA: msgId         TYPE string,
          current_date  TYPE string,
          lv_now        TYPE string,
          creation_date TYPE string,
          final_xml     TYPE string,
          loop_xml      TYPE string.

    lv_now = utclong_current( ).
    msgId = |{ lv_now(4) }-{ lv_now+5(2) }-{ lv_now+8(2) }_{ lv_now+11(2) }:{ lv_now+14(2) }:{ lv_now+17(2) }|.
    current_date = |{ lv_now(4) }-{ lv_now+5(2) }-{ lv_now+8(2) }|.

    creation_date = |{ lv_now(4) }-{ lv_now+5(2) }-{ lv_now+8(2) }T{ lv_now+11(2) }:{ lv_now+14(2) }:{ lv_now+17(2) }.{ lv_now+20(3) }{ lv_now+24(3) }Z|.

       SELECT SINGLE FROM I_JournalEntryItem
        FIELDS AccountingDocument , AccountingDocumentItem, CompanyCode ,FiscalYear,Supplier
        WHERE InvoiceReference = @wa_data-journal_entry
        AND   InvoiceReferenceFiscalYear = @wa_data-fiscal_year
        AND Ledger = '0L'
        INTO @DATA(ACC_DOC).

    IF abs( wa_data-invoice_value ) EQ abs( wa_data-amount_proposal ).
      DATA(lv_head) =
         |<soapenv:Envelope xmlns:soapenv="http://www.w3.org/2003/05/soap-envelope" xmlns:sfin="http://sap.com/xi/SAPSCORE/SFIN">| &&
         |<soapenv:Header/>| &&
         |<soapenv:Body>| &&
         |<sfin:JournalEntryBulkClearingRequest>| &&
         |<MessageHeader>| &&
         |<ID>{ msgId }</ID>| &&
         |<CreationDateTime>{ creation_date }</CreationDateTime>| &&
         |<TestDataIndicator>{ |false| }</TestDataIndicator>| &&
         |</MessageHeader>| &&
         |<JournalEntryClearingRequest>| &&
         |<MessageHeader>| &&

         |<ID>{ |SUB_| && msgId }</ID>| &&
         |<CreationDateTime>{ creation_date }</CreationDateTime>| &&
         |</MessageHeader>| &&
         |<JournalEntry>| &&
         |<CompanyCode>{ wa_data-company_code }</CompanyCode>| &&
         |<AccountingDocumentType>KA</AccountingDocumentType>| &&
         |<DocumentDate>{ current_date }</DocumentDate>| &&
         |<PostingDate>{ current_date }</PostingDate>| &&
         |<CurrencyCode>INR</CurrencyCode>| &&
         |<DocumentHeaderText>Clearing Entry</DocumentHeaderText>| &&

         |<APARItems>| &&
         |<ReferenceDocumentItem>1</ReferenceDocumentItem>| &&
         |<CompanyCode>{ wa_data-company_code }</CompanyCode>| &&
         |<AccountType>K</AccountType>| &&
         |<APARAccount>{ wa_data-supplier ALPHA = IN }</APARAccount>| &&
         |<FiscalYear>{ wa_data-fiscal_year }</FiscalYear>| &&
         |<AccountingDocument>{ wa_data-journal_entry }</AccountingDocument>| &&
         |<AccountingDocumentItem>1</AccountingDocumentItem>| &&
         |</APARItems>| &&

         |<APARItems>| &&
         |<ReferenceDocumentItem>2</ReferenceDocumentItem>| &&
         |<CompanyCode>{ wa_data-company_code }</CompanyCode>| &&
         |<AccountType>K</AccountType>| &&
         |<APARAccount>{ wa_data-supplier ALPHA = IN }</APARAccount>| &&
         |<FiscalYear>{ wa_data-fiscal_year }</FiscalYear>| &&
         |<AccountingDocument>{  ACC_DOC-AccountingDocument }</AccountingDocument>| &&
         |<AccountingDocumentItem>2</AccountingDocumentItem>| &&
         |</APARItems>| &&
         |</JournalEntry>|                           &&
         |</JournalEntryClearingRequest>|            &&
         |</sfin:JournalEntryBulkClearingRequest>|   &&
         |</soapenv:Body>|                           &&
         |</soapenv:Envelope>|.

      TRY.
          api_call( final_xml = lv_head ).
        CATCH cx_http_dest_provider_error INTO DATA(lx_dest).
          message = message && | [Clearing API - Destination Error: { lx_dest->get_text( ) }]|.
          RETURN.

        CATCH cx_web_http_client_error INTO DATA(lx_http).
          message = message && | [Clearing API - HTTP Error: { lx_http->get_text( ) }]|.
          RETURN.

        CATCH cx_web_message_error INTO DATA(lx_msg).
          message = message && | [Clearing API - Message Error: { lx_msg->get_text( ) }]|.
          RETURN.

        CATCH cx_root INTO DATA(lx_root).
          message = message && | [Clearing API - Unexpected Error: { lx_root->get_text( ) }]|.
          RETURN.
      ENDTRY.

*      WAIT UP TO 3 SECONDS.
      SELECT SINGLE FROM I_JournalEntryItem
     FIELDS ClearingJournalEntry , ClearingJournalEntryFiscalYear
     WHERE AccountingDocument = @wa_data-journal_entry
     AND FiscalYear   = @wa_data-fiscal_year
      AND Ledger = '0L'
     AND ClearingJournalEntry IS NOT INITIAL
     INTO @DATA(clearedEntry).

      IF clearedentry IS NOT INITIAL.

        UPDATE zvendor_payment
        SET clearing_acctg_document = @clearedentry-ClearingJournalEntry,
            clearing_doc_year  = @clearedentry-ClearingJournalEntryFiscalYear
        WHERE id_no = @wa_data-id_no
        and journal_entry = @wa_data-journal_entry.
        COMMIT WORK.
        message = |Document Cleared Successfully | &&
          |Payment Doc: { document } | &&
          |Clearing Doc: { clearedEntry-ClearingJournalEntry }|.

        RETURN.
      ELSE.
        message = |Document Clearing Failed| &&
            |Payment Doc: { document } |.
        RETURN.
      ENDIF.

    ELSE.
      SELECT FROM I_JournalEntryItem
     FIELDS SUM( DebitAmountInTransCrcy )
     WHERE InvoiceReference = @wa_data-journal_entry
     AND   InvoiceReferenceFiscalYear = @wa_data-fiscal_year
     AND Ledger = '0L'
     INTO @DATA(lv_total_debit).

      IF abs( wa_data-invoice_value ) EQ abs( lv_total_debit ).

        SELECT FROM I_JournalEntryItem
        FIELDS AccountingDocument , AccountingDocumentItem, CompanyCode ,FiscalYear,Supplier
        WHERE InvoiceReference = @wa_data-journal_entry
        AND   InvoiceReferenceFiscalYear = @wa_data-fiscal_year
        AND Ledger = '0L'
        INTO TABLE @DATA(it_table).

        DATA(lv_XML1) =
       |<soapenv:Envelope xmlns:soapenv="http://www.w3.org/2003/05/soap-envelope" xmlns:sfin="http://sap.com/xi/SAPSCORE/SFIN">| &&
       |<soapenv:Header/>| &&
       |<soapenv:Body>| &&
       |<sfin:JournalEntryBulkClearingRequest>| &&
       |<MessageHeader>| &&
       |<ID>{ msgId }</ID>| &&
       |<CreationDateTime>{ creation_date }</CreationDateTime>| &&
       |<TestDataIndicator>{ |false| }</TestDataIndicator>| &&
       |</MessageHeader>| &&
       |<JournalEntryClearingRequest>| &&
       |<MessageHeader>| &&
       |<ID>{ |SUB_| && msgId }</ID>| &&
       |<CreationDateTime>{ creation_date }</CreationDateTime>| &&
       |</MessageHeader>| &&
       |<JournalEntry>| &&
       |<CompanyCode>{ wa_data-company_code }</CompanyCode>| &&
       |<AccountingDocumentType>KA</AccountingDocumentType>| &&
       |<DocumentDate>{ current_date }</DocumentDate>| &&
       |<PostingDate>{ current_date }</PostingDate>| &&
       |<CurrencyCode>INR</CurrencyCode>|.
*       |<DocumentHeaderText>Clearing Entry</DocumentHeaderText>| .

        DATA lv_apar_xml TYPE string.
        DATA lv_ref_item TYPE i VALUE 1.
        data AccountingType type i .
        data invoiceAccounting type i .
        SELECT single FROM I_OperationalAcctgDocItem
        FIELDS AccountingDocument , AccountingDocumentItem, CompanyCode ,FiscalYear,Supplier
        WHERE AccountingDocument = @wa_data-journal_entry
        AND   FiscalYear = @wa_data-fiscal_year
        AND   FinancialAccountType = 'K'
        INTO @DATA(Acountitem).
         invoiceAccounting = |{ Acountitem-AccountingDocumentItem ALPHA = OUT }|.

        LOOP AT it_table INTO DATA(wa_table).

        SELECT single FROM I_OperationalAcctgDocItem
        FIELDS AccountingDocument , AccountingDocumentItem, CompanyCode ,FiscalYear,Supplier
        WHERE AccountingDocument = @wa_table-AccountingDocument
        AND   FiscalYear = @wa_table-FiscalYear
        AND   FinancialAccountType = 'K'
        INTO @DATA(AcountgType).
         AccountingType = |{ AcountgType-AccountingDocumentItem ALPHA = OUT }|.

            lv_XML1 = lv_XML1 &&
            |<APARItems>| &&
            |<ReferenceDocumentItem>{ lv_ref_item }</ReferenceDocumentItem>| &&
            |<CompanyCode>{ wa_table-CompanyCode }</CompanyCode>| &&
            |<AccountType>K</AccountType>| &&
            |<APARAccount>{ wa_table-supplier ALPHA = IN }</APARAccount>| &&
            |<FiscalYear>{ wa_table-FiscalYear }</FiscalYear>| &&
            |<AccountingDocument>{ wa_table-AccountingDocument }</AccountingDocument>| &&
            |<AccountingDocumentItem>{ AccountingType }</AccountingDocumentItem>| &&
*            |<AccountingDocumentItem>2</AccountingDocumentItem>| &&
            |</APARItems>| .
*          ELSE.
            lv_ref_item = lv_ref_item + 1.
*            lv_XML1 = lv_XML1 &&
*             |<APARItems>| &&
*             |<ReferenceDocumentItem>{ lv_ref_item }</ReferenceDocumentItem>| &&
*             |<CompanyCode>{ wa_table-CompanyCode }</CompanyCode>| &&
*             |<AccountType>K</AccountType>| &&
*             |<APARAccount>{ wa_table-supplier ALPHA = IN }</APARAccount>| &&
*             |<FiscalYear>{ wa_table-FiscalYear }</FiscalYear>| &&
*             |<AccountingDocument>{ wa_table-AccountingDocument }</AccountingDocument>| &&
*             |<AccountingDocumentItem>{ AccountingType }</AccountingDocumentItem>| &&
**             |<AccountingDocumentItem>2</AccountingDocumentItem>| &&
*             |</APARItems>| .
*          ENDIF.
        ENDLOOP.

        lv_XML1 = lv_XML1 &&
         |<APARItems>| &&
         |<ReferenceDocumentItem>{ lv_ref_item }</ReferenceDocumentItem>| &&
         |<CompanyCode>{ wa_data-company_code }</CompanyCode>| &&
         |<AccountType>K</AccountType>| &&
         |<APARAccount>{ wa_data-supplier ALPHA = IN }</APARAccount>| &&
         |<FiscalYear>{ wa_data-fiscal_year }</FiscalYear>| &&
         |<AccountingDocument>{ wa_data-journal_entry }</AccountingDocument>| &&
*         |<AccountingDocumentItem>2</AccountingDocumentItem>| &&
         |<AccountingDocumentItem>{ invoiceAccounting }</AccountingDocumentItem>| &&
         |</APARItems>| &&
         |</JournalEntry>| &&
         |</JournalEntryClearingRequest>| &&
         |</sfin:JournalEntryBulkClearingRequest>| &&
         |</soapenv:Body>| &&
         |</soapenv:Envelope>|.

        TRY.
            api_call( final_xml = lv_XML1 ).
          CATCH cx_http_dest_provider_error INTO DATA(lx_deste).
            message = message && | [Clearing API - Destination Error: { lx_deste->get_text( ) }]|.
            RETURN.

          CATCH cx_web_http_client_error INTO DATA(lx_httpe).
            message = message && | [Clearing API - HTTP Error: { lx_httpe->get_text( ) }]|.
            RETURN.

          CATCH cx_web_message_error INTO DATA(lx_msge).
            message = message && | [Clearing API - Message Error: { lx_msge->get_text( ) }]|.
            RETURN.

          CATCH cx_root INTO DATA(lx_roote).
            message = message && | [Clearing API - Unexpected Error: { lx_roote->get_text( ) }]|.
            RETURN.
        ENDTRY.

        SELECT SINGLE FROM I_JournalEntryItem
              FIELDS ClearingJournalEntry , ClearingJournalEntryFiscalYear
              WHERE AccountingDocument = @wa_data-journal_entry
              AND FiscalYear   = @wa_data-fiscal_year
              AND Ledger = '0L'
              AND ClearingJournalEntry IS NOT INITIAL
              INTO @DATA(clearEntry).

        IF clearEntry IS NOT INITIAL.

          UPDATE zvendor_payment
          SET clearing_acctg_document = @clearEntry-ClearingJournalEntry,
              clearing_doc_year  = @clearEntry-ClearingJournalEntryFiscalYear
          WHERE id_no = @wa_data-id_no
               and journal_entry = @wa_data-journal_entry.
          COMMIT WORK.

          message = |Document Cleared Successfully | &&
            |Payment Doc: { document } | &&
            |Clearing Doc: { clearEntry-ClearingJournalEntry }|.

          RETURN.
        ELSE.
          message = |Posting and Clearing Failed For. | &&
              |Invoice Value: { wa_data-invoice_value } | &&
              |Total Debit: { lv_total_debit }|.
          RETURN.
        ENDIF.

      ENDIF.
    ENDIF.

  ENDMETHOD.


  METHOD api_call.

    DATA rv_message_id TYPE string.

    TRY.
        rv_message_id = cl_system_uuid=>create_uuid_c36_static( ).

      CATCH cx_uuid_error INTO DATA(lx_uuid).
        rv_message_id = '00000000-0000-0000-0000-000000000000'.
    ENDTRY.

    rv_message_id = to_upper( rv_message_id ).

    DATA(suffix_url) = |https://my434946-api.s4hana.cloud.sap/sap/bc/srt/scs_ext/sap/journalentrybulkclearingreques/200/journalentrybulkclearingrequest/journalentrybulkclearingrequest_in?MessageId={ rv_message_id }|.

    DATA(lv_url) = |{ suffix_url } |.

    DATA lv_client2 TYPE REF TO if_web_http_client.
    TRY.
        DATA(dest2) = cl_http_destination_provider=>create_by_url( |{ suffix_url }| ).
        lv_client2 = cl_web_http_client_manager=>create_by_http_destination( dest2 ).


      CATCH cx_web_http_client_error INTO DATA(lx_dest_err).
        RETURN.
    ENDTRY.

    DATA(lo_request) = lv_client2->get_http_request( ).

    lo_request->set_header_field(
      i_name  = 'Content-Type'
      i_value = 'application/soap+xml; charset=utf-8'
    ).


    DATA i_username TYPE string VALUE 'INTEGRATION_SUITE_TECH'.
    DATA i_password TYPE string VALUE 'Ccn-b-YJzb<XYG}nL$S86[i3+\hFk@=D[ZKgnal\'.

    lo_request->set_authorization_basic(
        i_username = i_username
        i_password = i_password
    ).

    lo_request->set_content_type( 'application/soap+xml; charset=utf-8' ).
    lo_request->append_text( final_xml ).

    DATA(lo_response) = lv_client2->execute( if_web_http_client=>post ).

    DATA(lv_result) = lo_response->get_text( ).
    DATA(ls_status) = lo_response->get_status( ).

    IF ls_status-code = 202.
      DATA(mess) = |Document Posted and Cleared Successfully |.
      RETURN.

    ELSE.
      RAISE EXCEPTION TYPE cx_web_message_error
         MESSAGE ID '' TYPE 'E' NUMBER '001'
         WITH |API Error: { ls_status-code } - { lv_result }|.

    ENDIF.
  ENDMETHOD.
ENDCLASS.
