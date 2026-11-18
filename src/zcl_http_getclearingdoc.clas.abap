CLASS zcl_http_getclearingdoc DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_service_extension.

    CLASS-METHODS
      api_call
        IMPORTING final_xml TYPE string
        RAISING
                  cx_http_dest_provider_error
                  cx_web_http_client_error
                  cx_web_message_error.

    CLASS-METHODS clean_message_text
      IMPORTING
        iv_text         TYPE string
      RETURNING
        VALUE(rv_clean) TYPE string.

    CLASS-METHODS save_clearing_error
      IMPORTING
        iv_id_no         TYPE zvendor_payment-id_no
        iv_journal_entry TYPE zvendor_payment-journal_entry
        iv_company_code  TYPE zvendor_payment-company_code
        iv_fiscal_year   TYPE zvendor_payment-fiscal_year
        iv_error         TYPE string.
ENDCLASS.



CLASS ZCL_HTTP_GETCLEARINGDOC IMPLEMENTATION.


  METHOD if_http_service_extension~handle_request.



    TYPES: BEGIN OF ty_item,
             DbKey                 TYPE string,
             IdNo                  TYPE zvendor_payment-id_no,
             CompanyCode           TYPE i_journalentry-companycode,
             JournalEntry          TYPE string,
             FiscalYear            TYPE i_journalentry-fiscalyear,
             FiscalPeriod          TYPE string,
             Supplier              TYPE string,
             SupplierName          TYPE string,
             InvoiceDate           TYPE string,
             PostingDate           TYPE string,
             TransactionCurrency   TYPE string,
             InvoiceValue          TYPE string,
             AmountAlreadyPaid     TYPE string,
             BalanceToBePaid       TYPE string,
             AmountProposal        TYPE string,
             HouseBank             TYPE string,
             GlAccount             TYPE string,
             ProfitCenter          TYPE string,
             PurchaseOrder         TYPE string,
             Material              TYPE string,
             GrnNumber             TYPE string,
             GrnQuantity           TYPE string,
             PoQtyUnit             TYPE string,
             ConsumptionQuantity   TYPE string,
             ProposalStatus        TYPE string,
             Approval1Status       TYPE string,
             Approval1User         TYPE string,
             Approval2Status       TYPE string,
             PaymentStatus         TYPE string,
             UTRNumber             TYPE string,
             PostingDocument       TYPE string,
             ClearingAcctgDocument TYPE string,
             TransactionId         TYPE string,
           END OF ty_item,
           ty_items TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY,

           BEGIN OF ty_payload,
             action TYPE string,
             items  TYPE ty_items,
           END OF ty_payload.

    TYPES: BEGIN OF ty_error_entry,
             idno    TYPE zvendor_payment-id_no,
             message TYPE string,
           END OF ty_error_entry,
           ty_error_list TYPE STANDARD TABLE OF ty_error_entry WITH EMPTY KEY.


    DATA: ls_payload       TYPE ty_payload,
          lv_json          TYPE string,
          lv_messages      TYPE string,
          lv_success_count TYPE i,
          lv_fail_count    TYPE i,
          lv_result        TYPE string.

    lv_json = request->get_text( ).

    /ui2/cl_json=>deserialize(
      EXPORTING json = lv_json
      CHANGING  data = ls_payload ).

    IF ls_payload-items IS INITIAL.
      response->set_text( 'No items provided.' ).
      response->set_status( i_code = 400 ).
      RETURN.
    ENDIF.


    LOOP AT ls_payload-items ASSIGNING FIELD-SYMBOL(<ls_item>).
      DATA: org_item          TYPE string,
            AcctType          TYPE string,
            msgId             TYPE string,
            current_date      TYPE string,
            creation_date     TYPE string,
            lv_now            TYPE string,
            tb_now            TYPE string,
            lv_head           TYPE string,
            lv_XML1           TYPE string,
            lv_apar_xml       TYPE string,
            lv_uuid_full      TYPE string,
            lv_uuid_partial   TYPE string,
            final_xml         TYPE string,
            loop_xml          TYPE string,
            lv_ref_item       TYPE i,
            AccountingType    TYPE i,
            invoiceAccounting TYPE i,
            lv_total_debit    TYPE p LENGTH 16 DECIMALS 2.

      CLEAR: lv_result, org_item, AcctType, msgId,
             current_date, creation_date, lv_now, tb_now,
             lv_head, lv_XML1, lv_apar_xml,lv_uuid_full,lv_uuid_partial ,final_xml, loop_xml,
             lv_ref_item, AccountingType, invoiceAccounting,
             lv_total_debit.
      lv_ref_item = 1.

      DATA(lv_journal) = CONV belnr_d( |{ <ls_item>-journalentry ALPHA = IN }| ).

*     Pre Check Already Clear
      SELECT SINGLE FROM I_JournalEntryItem
        FIELDS AccountingDocument, AccountingDocumentItem, CompanyCode, FiscalYear,
               ClearingJournalEntry, ClearingJournalEntryFiscalYear
        WHERE AccountingDocument = @<ls_item>-postingdocument
        AND   FiscalYear   = @<ls_item>-fiscalyear
        AND   CompanyCode  = @<ls_item>-companycode
        AND   Ledger       = '0L'
        and   FinancialAccountType = 'K'
        AND   ClearingJournalEntry IS NOT INITIAL     "<-- INITIAL ko NOT INITIAL karo
        AND   IsReversal IS INITIAL AND IsReversed IS INITIAL
        INTO @DATA(AlreadyCleared).

      IF AlreadyCleared IS NOT INITIAL.
        UPDATE zvendor_payment
          SET clearing_acctg_document = @AlreadyCleared-ClearingJournalEntry,
              clearing_doc_year       = @AlreadyCleared-ClearingJournalEntryFiscalYear,
              clearingerror           = ''
          WHERE id_no         = @<ls_item>-idno
          AND   journal_entry = @lv_journal
          AND   company_code  = @<ls_item>-companycode
          AND   fiscal_year   = @<ls_item>-fiscalyear.
        COMMIT WORK AND WAIT.
        lv_success_count = lv_success_count + 1.
        lv_messages = lv_messages && |JournalEntry { lv_journal  } (ID { <ls_item>-idno }): Already cleared (Doc: { AlreadyCleared-ClearingJournalEntry }) |.


        CLEAR AlreadyCleared.
        CONTINUE.

      ELSE.
         UPDATE zvendor_payment
          SET clearing_acctg_document = '',
              clearing_doc_year       = '',
              clearingerror           = ''
          WHERE id_no         = @<ls_item>-idno
          AND   journal_entry = @lv_journal
          AND   company_code  = @<ls_item>-companycode
          AND   fiscal_year   = @<ls_item>-fiscalyear.
        COMMIT WORK.

        SELECT SINGLE FROM I_JournalEntryItem
          FIELDS AccountingDocument, AccountingDocumentItem, CompanyCode, FiscalYear, Supplier
          WHERE AccountingDocument  = @lv_journal
          AND   FiscalYear = @<ls_item>-fiscalyear
          AND   CompanyCode = @<ls_item>-companycode
          AND   Ledger                    = '0L'
          and   FinancialAccountType = 'K'
          AND ClearingJournalEntry IS INITIAL
          AND IsReversal IS INITIAL AND IsReversed IS INITIAL
          INTO @DATA(org_doc).
        Org_item = |{ org_doc-AccountingDocumentItem ALPHA = OUT }|.

        IF <ls_item>-postingdocument IS NOT INITIAL AND <ls_item>-clearingacctgdocument IS INITIAL.
          IF abs( <ls_item>-invoicevalue ) EQ abs( <ls_item>-amountproposal ).

            DATA(lv_today) = cl_abap_context_info=>get_system_date( ).

            lv_now = utclong_current( ).
            current_date  = |{ lv_now(4) }-{ lv_now+5(2) }-{ lv_now+8(2) }|.
            creation_date = |{ lv_now(4) }-{ lv_now+5(2) }-{ lv_now+8(2) }T{ lv_now+11(2) }:{ lv_now+14(2) }:{ lv_now+17(2) }.{ lv_now+20(3) }{ lv_now+24(3) }Z|.
            TRY.
                lv_uuid_full = cl_system_uuid=>create_uuid_c36_static( ).
              CATCH cx_uuid_error.
                lv_uuid_full = |F{ lv_now(4) }{ lv_now+5(2) }{ lv_now+8(2) }{ lv_now+11(2) }{ lv_now+14(2) }{ lv_now+17(2) }{ lv_now+20(6) }|.
            ENDTRY.
            REPLACE ALL OCCURRENCES OF '-' IN lv_uuid_full WITH ''.
            msgId = |F{ lv_uuid_full(31) }|.


            SELECT SINGLE FROM I_JournalEntryItem
             FIELDS AccountingDocument, AccountingDocumentItem, CompanyCode, FiscalYear, Supplier
             WHERE InvoiceReference          = @lv_journal
             AND   InvoiceReferenceFiscalYear = @<ls_item>-fiscalyear
             AND CompanyCode = @<ls_item>-companycode
             AND   Ledger                    = '0L'
             and   FinancialAccountType = 'K'
             AND ClearingJournalEntry IS INITIAL
             AND IsReversal IS INITIAL
             AND IsReversed IS INITIAL
             INTO @DATA(acc_doc).

            AcctType = |{ acc_doc-AccountingDocumentItem ALPHA = OUT }|.

            IF acc_doc-AccountingDocument IS INITIAL.
              DATA(message) = |Clearing Skipped: Reference invoice document not found for JE { lv_journal  } FY { <ls_item>-fiscalyear }|.
              save_clearing_error(
              iv_id_no         = <ls_item>-idno
              iv_journal_entry = lv_journal
              iv_company_code  = <ls_item>-companycode
              iv_fiscal_year   = <ls_item>-fiscalyear
              iv_error         = lv_result ).
              lv_fail_count = lv_fail_count + 1.
              lv_messages = lv_messages && |Clearing Skipped: Reference invoice document not found for JE { lv_journal } FY { <ls_item>-fiscalyear }|.
              CONTINUE.
            ENDIF.

            lv_head =
              |<soapenv:Envelope xmlns:soapenv="http://www.w3.org/2003/05/soap-envelope" xmlns:sfin="http://sap.com/xi/SAPSCORE/SFIN">| &&
              |<soapenv:Header/>| &&
              |<soapenv:Body>| &&
              |<sfin:JournalEntryBulkClearingRequest>| &&
              |<MessageHeader>| &&
              |<ID>{ msgId }</ID>| &&
              |<CreationDateTime>{ creation_date }</CreationDateTime>| &&
              |<TestDataIndicator>false</TestDataIndicator>| &&
              |</MessageHeader>| &&
              |<JournalEntryClearingRequest>| &&
              |<MessageHeader>| &&
              |<ID>{ |S_| && msgId }</ID>| &&
              |<CreationDateTime>{ creation_date }</CreationDateTime>| &&
              |</MessageHeader>| &&
              |<JournalEntry>| &&
              |<CompanyCode>{ <ls_item>-companycode }</CompanyCode>| &&
              |<AccountingDocumentType>KA</AccountingDocumentType>| &&
              |<DocumentDate>{ current_date }</DocumentDate>| &&
              |<PostingDate>{ current_date }</PostingDate>| &&
              |<CurrencyCode>INR</CurrencyCode>| &&
              |<DocumentHeaderText>Clearing Entry</DocumentHeaderText>| &&

              |<APARItems>| &&
              |<ReferenceDocumentItem>1</ReferenceDocumentItem>| &&
              |<CompanyCode>{ <ls_item>-companycode }</CompanyCode>| &&
              |<AccountType>K</AccountType>| &&
              |<APARAccount>{ <ls_item>-supplier ALPHA = IN }</APARAccount>| &&
              |<FiscalYear>{ <ls_item>-fiscalyear }</FiscalYear>| &&
              |<AccountingDocument>{ <ls_item>-journalentry }</AccountingDocument>| &&
              |<AccountingDocumentItem>{ Org_item }</AccountingDocumentItem>| &&
              |</APARItems>| &&

              |<APARItems>| &&
              |<ReferenceDocumentItem>2</ReferenceDocumentItem>| &&
              |<CompanyCode>{ acc_doc-CompanyCode }</CompanyCode>| &&
              |<AccountType>K</AccountType>| &&
              |<APARAccount>{ acc_doc-supplier ALPHA = IN }</APARAccount>| &&
              |<FiscalYear>{ acc_doc-FiscalYear }</FiscalYear>| &&
              |<AccountingDocument>{ acc_doc-AccountingDocument }</AccountingDocument>| &&
              |<AccountingDocumentItem>{ AcctType }</AccountingDocumentItem>| &&
              |</APARItems>| &&
              |</JournalEntry>| &&
              |</JournalEntryClearingRequest>| &&
              |</sfin:JournalEntryBulkClearingRequest>| &&
              |</soapenv:Body>| &&
              |</soapenv:Envelope>|.

            TRY.
                api_call( final_xml = lv_head ).
                WAIT UP TO 1 SECONDS.
                SELECT SINGLE FROM I_JournalEntryItem
                  FIELDS ClearingJournalEntry , ClearingJournalEntryFiscalYear
                  WHERE AccountingDocument = @lv_journal
                  AND FiscalYear   = @<ls_item>-fiscalyear
                  AND CompanyCode = @<ls_item>-companycode
                  AND Ledger = '0L'
                  and   FinancialAccountType = 'K'
                  AND ClearingJournalEntry IS NOT INITIAL
                  AND IsReversal IS INITIAL AND IsReversed IS INITIAL
                  INTO @DATA(clearEntry).

                IF clearEntry IS NOT INITIAL.
                  UPDATE zvendor_payment
                  SET clearing_acctg_document = @clearEntry-ClearingJournalEntry,
                  clearing_doc_year  = @clearEntry-ClearingJournalEntryFiscalYear,
                  clearingerror = ''
                  WHERE id_no = @<ls_item>-idno
                  AND journal_entry = @<ls_item>-journalentry
                  AND company_code = @<ls_item>-companycode
                  AND fiscal_year = @<ls_item>-fiscalyear.
                  COMMIT WORK AND WAIT.

                  IF sy-dbcnt = 0.

                    UPDATE zvendor_payment
                    SET clearing_acctg_document = @clearEntry-ClearingJournalEntry,
                    clearing_doc_year  = @clearEntry-ClearingJournalEntryFiscalYear,
                    clearingerror = ''
                    WHERE id_no = @<ls_item>-idno
                    AND journal_entry = @<ls_item>-journalentry
                    AND company_code = @<ls_item>-companycode
                    AND fiscal_year = @<ls_item>-fiscalperiod.
                    COMMIT WORK AND WAIT.

                  ENDIF.
                  lv_result = |Document { lv_journal  } Cleared Successfully (Ref Doc: { clearEntry-ClearingJournalEntry })|.
                  lv_success_count = lv_success_count + 1.
                  lv_messages = lv_messages && |JournalEntry { lv_journal  } (ID { <ls_item>-idno }): { lv_result } |.
                 clear: clearEntry.
                  CONTINUE.
                ENDIF.

              CATCH cx_http_dest_provider_error INTO DATA(lx_dest).
                DATA(lv_clr_reason1) = clean_message_text( lx_dest->get_text( ) ).
                IF lv_clr_reason1 IS INITIAL.
                  lv_clr_reason1 = |Unable to connect to the clearing service.|.
                ENDIF.
                lv_result = |Clearing Failed: { lv_clr_reason1 }|.
                save_clearing_error( iv_id_no = <ls_item>-idno iv_journal_entry = lv_journal
                                     iv_company_code = <ls_item>-companycode iv_fiscal_year = <ls_item>-fiscalyear
                                     iv_error = lv_result ).
                lv_fail_count = lv_fail_count + 1.
                lv_messages = lv_messages && |JournalEntry { <ls_item>-journalentry } (ID { <ls_item>-idno }): { lv_result } |.
                CONTINUE.

              CATCH cx_web_http_client_error INTO DATA(lx_http).
                DATA(lv_clr_reason2) = clean_message_text( lx_http->get_text( ) ).
                IF lv_clr_reason2 IS INITIAL.
                  lv_clr_reason2 = |The clearing service did not respond properly.|.
                ENDIF.
                lv_result = |Clearing Failed: { lv_clr_reason2 }|.
                save_clearing_error( iv_id_no = <ls_item>-idno iv_journal_entry = lv_journal
                                     iv_company_code = <ls_item>-companycode iv_fiscal_year = <ls_item>-fiscalyear
                                     iv_error = lv_result ).
                lv_fail_count = lv_fail_count + 1.
                lv_messages = lv_messages && |JournalEntry { <ls_item>-journalentry } (ID { <ls_item>-idno }): { lv_result } |.
                CONTINUE.

              CATCH cx_web_message_error INTO DATA(lx_msg).
                DATA(lv_clr_reason3) = clean_message_text( lx_msg->get_text( ) ).
                IF lv_clr_reason3 IS INITIAL.
                  lv_clr_reason3 = |The clearing service rejected the request.|.
                ENDIF.
                lv_result = |Clearing Failed: { lv_clr_reason3 }|.
                save_clearing_error( iv_id_no = <ls_item>-idno iv_journal_entry = lv_journal
                                     iv_company_code = <ls_item>-companycode iv_fiscal_year = <ls_item>-fiscalyear
                                     iv_error = lv_result ).
                lv_fail_count = lv_fail_count + 1.
                lv_messages = lv_messages && |JournalEntry { <ls_item>-journalentry } (ID { <ls_item>-idno }): { lv_result } |.
                CONTINUE.

              CATCH cx_root INTO DATA(lx_root).
                DATA(lv_clr_reason4) = clean_message_text( lx_root->get_text( ) ).
                IF lv_clr_reason4 IS INITIAL.
                  lv_clr_reason4 = |An unexpected issue occurred during clearing.|.
                ENDIF.
                lv_result = |Clearing Failed: { lv_clr_reason4 }|.
                save_clearing_error( iv_id_no = <ls_item>-idno iv_journal_entry = lv_journal
                                     iv_company_code = <ls_item>-companycode iv_fiscal_year = <ls_item>-fiscalyear
                                     iv_error = lv_result ).
                lv_fail_count = lv_fail_count + 1.
                lv_messages = lv_messages && |JournalEntry { <ls_item>-journalentry } (ID { <ls_item>-idno }): { lv_result } |.
                CONTINUE.
            ENDTRY.
            lv_result = |Clearing Failed: Request was accepted but no clearing document was generated for JE { <ls_item>-journalentry }. Please verify in SAP.|.
            save_clearing_error( iv_id_no = <ls_item>-idno iv_journal_entry = lv_journal
                                 iv_company_code = <ls_item>-companycode iv_fiscal_year = <ls_item>-fiscalyear
                                 iv_error = lv_result ).
            lv_fail_count = lv_fail_count + 1.
            lv_messages = lv_messages && |JournalEntry { <ls_item>-journalentry } (ID { <ls_item>-idno }): { lv_result } |.
            CONTINUE.
          ELSE.

            SELECT FROM I_JournalEntryItem
         FIELDS SUM( DebitAmountInTransCrcy )
         WHERE InvoiceReference = @lv_journal
         AND   InvoiceReferenceFiscalYear = @<ls_item>-fiscalyear
         AND CompanyCode = @<ls_item>-companycode
         AND ClearingJournalEntry IS INITIAL
         AND IsReversal IS INITIAL
         AND IsReversed IS INITIAL
         AND Ledger = '0L'
         and FinancialAccountType = 'K'
         INTO @lv_total_debit.

            IF abs( <ls_item>-invoicevalue ) EQ abs( lv_total_debit ).

              TRY.
                  lv_uuid_partial = cl_system_uuid=>create_uuid_c36_static( ).
                CATCH cx_uuid_error.
                  lv_uuid_partial = |P{ lv_now(4) }{ lv_now+5(2) }{ lv_now+8(2) }{ lv_now+11(2) }{ lv_now+14(2) }{ lv_now+17(2) }{ lv_now+20(6) }|.
              ENDTRY.
              REPLACE ALL OCCURRENCES OF '-' IN lv_uuid_partial WITH ''.
              msgId = |P{ lv_uuid_partial(31) }|.

              SELECT FROM I_JournalEntryItem
               FIELDS AccountingDocument , AccountingDocumentItem, CompanyCode ,FiscalYear,Supplier
               WHERE InvoiceReference = @lv_journal
               AND   InvoiceReferenceFiscalYear = @<ls_item>-fiscalyear
               AND CompanyCode = @<ls_item>-companycode
               AND ClearingJournalEntry IS INITIAL
               AND IsReversal IS INITIAL
               AND IsReversed IS INITIAL
               AND Ledger = '0L'
               and FinancialAccountType = 'K'
               INTO TABLE @DATA(it_table).

              tb_now = utclong_current( ).

              IF current_date IS INITIAL.
                current_date  = |{ tb_now(4) }-{ tb_now+5(2) }-{ tb_now+8(2) }|.
              ENDIF.

              IF creation_date IS INITIAL.
                creation_date = |{ tb_now(4) }-{ tb_now+5(2) }-{ tb_now+8(2) }T{ tb_now+11(2) }:{ tb_now+14(2) }:{ tb_now+17(2) }.{ tb_now+20(3) }{ tb_now+24(3) }Z|.
              ENDIF.


              lv_XML1 =
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
           |<ID>{ |S_| && msgId }</ID>| &&
           |<CreationDateTime>{ creation_date }</CreationDateTime>| &&
           |</MessageHeader>| &&
           |<JournalEntry>| &&
           |<CompanyCode>{ <ls_item>-companycode }</CompanyCode>| &&
           |<AccountingDocumentType>KA</AccountingDocumentType>| &&
           |<DocumentDate>{ current_date }</DocumentDate>| &&
           |<PostingDate>{ current_date }</PostingDate>| &&
           |<CurrencyCode>INR</CurrencyCode>|.

              SELECT SINGLE FROM I_OperationalAcctgDocItem
              FIELDS AccountingDocument , AccountingDocumentItem, CompanyCode ,FiscalYear,Supplier
              WHERE AccountingDocument = @lv_journal
              AND   FiscalYear = @<ls_item>-fiscalyear
              AND CompanyCode = @<ls_item>-companycode
              AND   FinancialAccountType = 'K'
              INTO @DATA(Acountitem).

              invoiceAccounting = |{ Acountitem-AccountingDocumentItem ALPHA = OUT }|.

              LOOP AT it_table INTO DATA(wa_table).

                SELECT SINGLE FROM I_OperationalAcctgDocItem
                FIELDS AccountingDocument , AccountingDocumentItem, CompanyCode ,FiscalYear,Supplier
                WHERE AccountingDocument = @wa_table-AccountingDocument
                AND CompanyCode = @<ls_item>-companycode
                AND   FiscalYear = @<ls_item>-fiscalyear
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
                      |</APARItems>| .

                lv_ref_item = lv_ref_item + 1.
              ENDLOOP.
              lv_XML1 = lv_XML1 &&
             |<APARItems>| &&
             |<ReferenceDocumentItem>{ lv_ref_item }</ReferenceDocumentItem>| &&
             |<CompanyCode>{ <ls_item>-companycode }</CompanyCode>| &&
             |<AccountType>K</AccountType>| &&
             |<APARAccount>{ <ls_item>-supplier ALPHA = IN }</APARAccount>| &&
             |<FiscalYear>{ <ls_item>-fiscalyear }</FiscalYear>| &&
             |<AccountingDocument>{ <ls_item>-journalentry }</AccountingDocument>| &&
             |<AccountingDocumentItem>{ invoiceAccounting }</AccountingDocumentItem>| &&
             |</APARItems>| &&
             |</JournalEntry>| &&
             |</JournalEntryClearingRequest>| &&
             |</sfin:JournalEntryBulkClearingRequest>| &&
             |</soapenv:Body>| &&
             |</soapenv:Envelope>|.

              TRY.
                  api_call( final_xml = lv_XML1 ).
                  WAIT UP TO 1 SECONDS.
                  SELECT SINGLE FROM I_JournalEntryItem
                    FIELDS ClearingJournalEntry , ClearingJournalEntryFiscalYear
                    WHERE AccountingDocument = @lv_journal
                    AND FiscalYear   = @<ls_item>-fiscalyear
                    AND CompanyCode = @<ls_item>-companycode
                    AND Ledger = '0L'
                    and FinancialAccountType = 'K'
                    AND ClearingJournalEntry IS NOT INITIAL
                    AND IsReversal IS INITIAL
                    AND IsReversed IS INITIAL
                    INTO @DATA(clrEnty).

                  IF clrEnty IS NOT INITIAL.
                    UPDATE zvendor_payment
                      SET clearing_acctg_document = @clrEnty-ClearingJournalEntry,
                          clearing_doc_year       = @clrEnty-ClearingJournalEntryFiscalYear,
                          clearingerror = ''
                      WHERE id_no         = @<ls_item>-idno
                        AND journal_entry = @<ls_item>-journalentry
                        AND fiscal_year   = @<ls_item>-fiscalyear
                        AND company_code  = @<ls_item>-companycode.
                    COMMIT WORK AND WAIT.

                    IF sy-dbcnt = 0.
                      UPDATE zvendor_payment
                                   SET clearing_acctg_document = @clrEnty-ClearingJournalEntry,
                                       clearing_doc_year       = @clrEnty-ClearingJournalEntryFiscalYear,
                                       clearingerror = ''
                                  WHERE id_no         = @<ls_item>-idno
                        AND journal_entry = @<ls_item>-journalentry
                        AND fiscal_year   = @<ls_item>-fiscalyear
                        AND company_code  = @<ls_item>-companycode.
                      COMMIT WORK AND WAIT.
                    ENDIF.
                    lv_result = |Document { <ls_item>-journalentry } Cleared Successfully ( Doc: { clrEnty-ClearingJournalEntry })|.
                    lv_success_count = lv_success_count + 1.
                    lv_messages = lv_messages && |JournalEntry { <ls_item>-journalentry } (ID { <ls_item>-idno }): { lv_result } |.
                    clear:clrEnty.
                    CONTINUE.
                  ENDIF.

                CATCH cx_http_dest_provider_error INTO lx_dest.
                  DATA(lv_clr_reason5) = clean_message_text( lx_dest->get_text( ) ).
                  IF lv_clr_reason5 IS INITIAL.
                    lv_clr_reason5 = |Unable to connect to the clearing service.|.
                  ENDIF.
                  lv_result = |Clearing Failed: { lv_clr_reason5 }|.
                  save_clearing_error( iv_id_no = <ls_item>-idno iv_journal_entry = lv_journal
                                       iv_company_code = <ls_item>-companycode iv_fiscal_year = <ls_item>-fiscalyear
                                       iv_error = lv_result ).
                  lv_fail_count = lv_fail_count + 1.
                  lv_messages = lv_messages && |JournalEntry { <ls_item>-journalentry } (ID { <ls_item>-idno }): { lv_result } |.
                  CONTINUE.


                CATCH cx_web_http_client_error INTO lx_http.
                  DATA(lv_clr_reason6) = clean_message_text( lx_http->get_text( ) ).
                  IF lv_clr_reason6 IS INITIAL.
                    lv_clr_reason6 = |The clearing service did not respond properly.|.
                  ENDIF.
                  lv_result = |Clearing Failed: { lv_clr_reason6 }|.
                  save_clearing_error( iv_id_no = <ls_item>-idno iv_journal_entry = lv_journal
                                       iv_company_code = <ls_item>-companycode iv_fiscal_year = <ls_item>-fiscalyear
                                       iv_error = lv_result ).
                  lv_fail_count = lv_fail_count + 1.
                  lv_messages = lv_messages && |JournalEntry { <ls_item>-journalentry } (ID { <ls_item>-idno }): { lv_result } |.
                  CONTINUE.


                CATCH cx_web_message_error INTO lx_msg.
                  DATA(lv_clr_reason7) = clean_message_text( lx_msg->get_text( ) ).
                  IF lv_clr_reason7 IS INITIAL.
                    lv_clr_reason7 = |The clearing service rejected the request.|.
                  ENDIF.
                  lv_result = |Clearing Failed: { lv_clr_reason7 }|.
                  save_clearing_error( iv_id_no = <ls_item>-idno iv_journal_entry = lv_journal
                                       iv_company_code = <ls_item>-companycode iv_fiscal_year = <ls_item>-fiscalyear
                                       iv_error = lv_result ).
                  lv_fail_count = lv_fail_count + 1.
                  lv_messages = lv_messages && |JournalEntry { <ls_item>-journalentry } (ID { <ls_item>-idno }): { lv_result } |.
                  CONTINUE.

                CATCH cx_root INTO lx_root.
                  DATA(lv_clr_reason8) = clean_message_text( lx_root->get_text( ) ).
                  IF lv_clr_reason8 IS INITIAL.
                    lv_clr_reason8 = |An unexpected issue occurred during clearing.|.
                  ENDIF.
                  lv_result = |Clearing Failed: { lv_clr_reason8 }|.
                  save_clearing_error( iv_id_no = <ls_item>-idno iv_journal_entry = lv_journal
                                       iv_company_code = <ls_item>-companycode iv_fiscal_year = <ls_item>-fiscalyear
                                       iv_error = lv_result ).
                  lv_fail_count = lv_fail_count + 1.
                  lv_messages = lv_messages && |JournalEntry { <ls_item>-journalentry } (ID { <ls_item>-idno }): { lv_result } |.
                  CONTINUE.
              ENDTRY.
              lv_result = |Clearing Failed: Request was accepted but no clearing document was generated for JE { <ls_item>-journalentry }. Please verify in SAP.|.
              save_clearing_error( iv_id_no = <ls_item>-idno iv_journal_entry = lv_journal
                                   iv_company_code = <ls_item>-companycode iv_fiscal_year = <ls_item>-fiscalyear
                                   iv_error = lv_result ).
              lv_fail_count = lv_fail_count + 1.
              lv_messages = lv_messages && |JournalEntry { <ls_item>-journalentry } (ID { <ls_item>-idno }): { lv_result } |.
              CONTINUE.

            ELSE.
              lv_result = |Clearing skipped: partial payment - invoice value differs from amount proposal|.
              save_clearing_error( iv_id_no = <ls_item>-idno iv_journal_entry = lv_journal
                                   iv_company_code = <ls_item>-companycode iv_fiscal_year = <ls_item>-fiscalyear
                                   iv_error = lv_result ).
              lv_fail_count = lv_fail_count + 1.
              lv_messages = lv_messages && |JournalEntry { <ls_item>-journalentry } (ID { <ls_item>-idno }): { lv_result } |.
              CONTINUE.
            ENDIF.

          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.
    response->set_text( |Processed: { lv_success_count } succeeded, { lv_fail_count } failed. { lv_messages }| ).

    IF lv_fail_count > 0.
      response->set_status( i_code = 400 i_reason = 'Bad Request' ).
    ELSE.
      response->set_status( i_code = 200 i_reason = 'OK' ).
    ENDIF.


  ENDMETHOD.


  METHOD save_clearing_error.

    DATA: lv_existing_err TYPE string,
          lv_final_err    TYPE string.

    SELECT SINGLE clearingerror
      FROM zvendor_payment
      WHERE id_no         = @iv_id_no
        AND journal_entry = @iv_journal_entry
        AND company_code  = @iv_company_code
        AND fiscal_year   = @iv_fiscal_year
      INTO @lv_existing_err.

    IF lv_existing_err IS NOT INITIAL.
      lv_final_err = |{ lv_existing_err } | && iv_error.
    ELSE.
      lv_final_err = iv_error.
    ENDIF.
    lv_final_err = clean_message_text( lv_final_err ).

    UPDATE zvendor_payment
      SET clearingerror = @lv_final_err
      WHERE id_no         = @iv_id_no
        AND journal_entry = @iv_journal_entry
        AND company_code  = @iv_company_code
        AND fiscal_year   = @iv_fiscal_year.
    COMMIT WORK AND WAIT.

  ENDMETHOD.


  METHOD clean_message_text.
    DATA: lv_pos_lt TYPE i,
          lv_pos_gt TYPE i,
          lv_before TYPE string,
          lv_after  TYPE string,
          lv_tmp    TYPE string.

    rv_clean = iv_text.

    IF rv_clean IS INITIAL.
      RETURN.
    ENDIF.

    DO 1000 TIMES.
      FIND '<' IN rv_clean MATCH OFFSET lv_pos_lt.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      FIND '>' IN SECTION OFFSET lv_pos_lt OF rv_clean MATCH OFFSET lv_pos_gt.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      lv_before = rv_clean(lv_pos_lt).
      lv_after  = substring( val = rv_clean off = lv_pos_gt + 1 ).
      rv_clean  = |{ lv_before } { lv_after }|.
    ENDDO.

    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf          IN rv_clean WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline        IN rv_clean WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN rv_clean WITH ` `.

    DATA(lv_two_spaces) = | { space }|.

    IF rv_clean IS NOT INITIAL.
      DO 100 TIMES.
        IF rv_clean NS lv_two_spaces.
          EXIT.
        ENDIF.
        REPLACE ALL OCCURRENCES OF lv_two_spaces IN rv_clean WITH ` `.
      ENDDO.
    ENDIF.

    CONDENSE rv_clean.

    IF strlen( rv_clean ) > 500.
      lv_tmp = rv_clean(497).
      rv_clean = |{ lv_tmp }...|.
    ENDIF.
  ENDMETHOD.


  METHOD api_call.

    DATA rv_message_id TYPE string.

    TRY.
        rv_message_id = cl_system_uuid=>create_uuid_c36_static( ).

      CATCH cx_uuid_error INTO DATA(lx_uuid).
        rv_message_id = '00000000-0000-0000-0000-000000000000'.
    ENDTRY.
    DATA suffix_url TYPE string.
    rv_message_id = to_upper( rv_message_id ).

    DATA(lv_url) = cl_abap_context_info=>get_system_url(  ).
    IF lv_url = 'my434946.s4hana.cloud.sap'.
      suffix_url = |https://my434946-api.s4hana.cloud.sap/sap/bc/srt/scs_ext/sap/journalentrybulkclearingreques/200/journalentrybulkclearingrequest/journalentrybulkclearingrequest_in?MessageId={ rv_message_id }|.
    ELSEIF lv_url = 'my436356.s4hana.cloud.sap'.
      suffix_url = |https://my436356-api.s4hana.cloud.sap/sap/bc/srt/scs_ext/sap/journalentrybulkclearingreques/200/journalentrybulkclearingrequest/journalentrybulkclearingrequest_in?MessageId={ rv_message_id }|.
    ELSEIF lv_url = 'my438594.s4hana.cloud.sap'.
      suffix_url = |https://my438594-api.s4hana.cloud.sap/sap/bc/srt/scs_ext/sap/journalentrybulkclearingreques/200/journalentrybulkclearingrequest/journalentrybulkclearingrequest_in?MessageId={ rv_message_id }|.
    ELSE.
      RAISE EXCEPTION TYPE cx_web_message_error
        MESSAGE ID '' TYPE 'E' NUMBER '001'
        WITH |Unknown system { lv_url } - clearing URL not configured.|.
    ENDIF.

    DATA lv_client2 TYPE REF TO if_web_http_client.
    TRY.
        DATA(dest2) = cl_http_destination_provider=>create_by_url( |{ suffix_url }| ).
        lv_client2 = cl_web_http_client_manager=>create_by_http_destination( dest2 ).

      CATCH cx_web_http_client_error INTO DATA(lx_dest_err).
        RAISE EXCEPTION lx_dest_err.
      CATCH cx_http_dest_provider_error INTO DATA(lx_dest_prov).
        RAISE EXCEPTION lx_dest_prov.
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
      RETURN.
    ELSE.
      DATA(lv_backend_reason) = clean_message_text( lv_result ).

      IF lv_backend_reason IS INITIAL.
        lv_backend_reason = |The clearing service returned an unexpected response (HTTP { ls_status-code }).|.
      ENDIF.

      RAISE EXCEPTION TYPE cx_web_message_error
        MESSAGE ID '' TYPE 'E' NUMBER '001'
        WITH lv_backend_reason.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
