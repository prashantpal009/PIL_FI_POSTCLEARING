CLASS zcl_http_invocie_posting DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES if_http_service_extension.

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
             SpecialGLCODE              TYPE zvendor_payment-speciaglcode,
           END OF ty_invoice_details.

    TYPES: tt_invoice_details TYPE TABLE OF ty_invoice_details
                     WITH EMPTY KEY.

    TYPES: BEGIN OF ty_item,
             dbkey        TYPE string,
             journalentry TYPE string,
             FiscalYear   TYPE String,
             CompanyCode  TYPE string,
             IdNo         TYPE string,
           END OF ty_item,
           ty_items TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             items       TYPE ty_items,
             postingdate TYPE string,
           END OF ty_payload.

    CLASS-DATA: lv_je_alpha TYPE belnr_d.
    CLASS-METHODS postData
      IMPORTING
        request        TYPE REF TO if_web_http_request
      RETURNING
        VALUE(message) TYPE string.

    CLASS-METHODS reverse_journal_entry
      IMPORTING
        iv_journal_entry  TYPE zvendor_payment-journal_entry
        iv_fiscal_year    TYPE zvendor_payment-fiscal_year
        iv_company_code   TYPE zvendor_payment-company_code
      RETURNING
        VALUE(rv_message) TYPE string.

    CLASS-METHODS postInvoiceData
      IMPORTING
        wa_data             TYPE ty_invoice_details
        c_id                TYPE string
        lv_inv_ref_doc      TYPE string
        lv_assignmentrefadv TYPE string
        iv_posting_date     TYPE d
      RETURNING
        VALUE(message)      TYPE string.

    CLASS-METHODS postGroupedInvoiceData
      IMPORTING
        it_group        TYPE tt_invoice_details
        c_id            TYPE string
        iv_posting_date TYPE d
      RETURNING
        VALUE(message)  TYPE string.

    CLASS-METHODS clean_message_text
      IMPORTING
        iv_text         TYPE string
      RETURNING
        VALUE(rv_clean) TYPE string.


  PROTECTED SECTION.
  PRIVATE SECTION.

ENDCLASS.



CLASS ZCL_HTTP_INVOCIE_POSTING IMPLEMENTATION.


  METHOD if_http_service_extension~handle_request.

    CASE request->get_method( ).
      WHEN CONV string( if_web_http_client=>post ).
        DATA(lv_message) = postData( request ).
        response->set_text( lv_message ).
        IF lv_message CS 'Error' OR lv_message CS 'error'
        OR lv_message CS 'No items' OR lv_message CS 'already posted'
        OR lv_message CS 'Failed' OR lv_message CS 'failed'.
          response->set_status( i_code = 400 i_reason = 'Bad Request' ).
        ELSE.
          response->set_status( i_code = 200 i_reason = 'OK' ).
        ENDIF.
      WHEN OTHERS.
        response->set_status( i_code = 405 i_reason = 'Method Not Allowed' ).
    ENDCASE.

  ENDMETHOD.


  METHOD postdata.

    DATA: ls_payload          TYPE ty_payload,
          lv_json             TYPE string,
          lv_messages         TYPE string,
          lv_success_count    TYPE i,
          lv_fail_count       TYPE i,
          invoicedetails      TYPE ty_invoice_details,
          lv_db_key           TYPE zvendor_payment-db_key,
          lv_journal          TYPE belnr_d,
          lv_posting_id       TYPE string,
          lv_doc              TYPE string,
          lv_inv_ref_doc      TYPE string,
          lv_result           TYPE string,
          lv_assignmentrefadv TYPE string,
          lv_existing_status  TYPE zvendor_payment.

    DATA: lt_normal TYPE tt_invoice_details.


    TRY.

        lv_json = request->get_text( ).

        /ui2/cl_json=>deserialize(
          EXPORTING json = lv_json
          CHANGING  data = ls_payload ).

        IF ls_payload-items IS INITIAL.
          message = '{"error":"No items provided"}'.
          RETURN.
        ENDIF.

        DATA: lv_posting_date TYPE d.

        IF ls_payload-postingdate IS NOT INITIAL.
          lv_posting_date = ls_payload-postingdate(4) &&
                            ls_payload-postingdate+5(2) &&
                            ls_payload-postingdate+8(2).
        ELSE.
          lv_posting_date = cl_abap_context_info=>get_system_date( ).
        ENDIF.

        LOOP AT ls_payload-items INTO DATA(wa).

          CLEAR: invoicedetails, lv_doc, lv_inv_ref_doc, lv_result,
                 lv_existing_status, lv_assignmentrefadv.

          lv_je_alpha = |{ wa-journalentry ALPHA = IN }|.

          SELECT SINGLE *
            FROM zvendor_payment
            WHERE id_no         = @wa-idno
              AND journal_entry = @lv_je_alpha
              AND company_code = @wa-companycode
              AND fiscal_year  = @wa-fiscalyear
            INTO @lv_existing_status.

          IF lv_existing_status IS INITIAL.
            lv_fail_count = lv_fail_count + 1.
            lv_messages = lv_messages &&
              |Document { lv_je_alpha }-{ wa-companycode }-{ wa-fiscalyear } (ID { wa-idno }): Error - Record not found in vendor payment table. |.
            CONTINUE.
          ENDIF.

          IF lv_existing_status-post_status = 'POSTED'.
            lv_fail_count = lv_fail_count + 1.
            lv_messages = lv_messages &&
              |JournalEntry { lv_je_alpha }-{ wa-companycode }-{ wa-fiscalyear } (ID { wa-idno }): This invoice is already posted. |.
            CONTINUE.
          ENDIF.

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
              a~post_status,
              a~speciaglcode
            WHERE a~id_no         = @wa-idno
              AND a~journal_entry = @lv_je_alpha
              AND a~company_code = @wa-companycode
              AND a~fiscal_year  = @wa-fiscalyear
            INTO @invoicedetails.

          IF invoicedetails-utrnumber IS INITIAL.
            lv_fail_count = lv_fail_count + 1.
            lv_messages = lv_messages &&
              |JournalEntry { wa-journalentry }-{ wa-companycode }-{ wa-fiscalyear } (ID { wa-idno }): Error - UTR number is missing. Posting not allowed. |.
            CONTINUE.
          ENDIF.

          IF invoicedetails-specialglcode = 'F'.

            TRY.
                DATA(cid_f) = to_upper( cl_uuid_factory=>create_system_uuid( )->create_uuid_x16( ) ).
              CATCH cx_uuid_error.
                lv_fail_count = lv_fail_count + 1.
                lv_messages = lv_messages && |JournalEntry { wa-journalentry }-{ wa-companycode }-{ wa-fiscalyear } (ID { wa-idno }): Error - Unable to generate a unique posting reference. Please try again. |.
                CONTINUE.
            ENDTRY.

            lv_doc              = |{ invoicedetails-journal_entry ALPHA = IN }|.
            lv_inv_ref_doc      = |{ lv_doc }{ invoicedetails-fiscal_year }{ invoicedetails-accounting_document_item }|.
            lv_assignmentrefadv = |{ lv_doc }{ invoicedetails-fiscal_year }{ invoicedetails-company_code }|.

            lv_result = postInvoiceData(
              wa_data             = invoicedetails
              c_id                = cid_f
              lv_inv_ref_doc      = lv_inv_ref_doc
              lv_assignmentrefadv = lv_assignmentrefadv
              iv_posting_date     = lv_posting_date ).

            IF lv_result CS 'Successfully'
               AND lv_result NS 'Failed' AND lv_result NS 'failed'
               AND lv_result NS 'Error'  AND lv_result NS 'error'
               AND lv_result NS 'BUT '.
              lv_success_count = lv_success_count + 1.
            ELSE.
              lv_fail_count = lv_fail_count + 1.
            ENDIF.

            lv_messages = lv_messages && |JournalEntry { wa-journalentry } (ID { wa-idno }): { lv_result } |.
            CONTINUE.
          ENDIF.

          APPEND invoicedetails TO lt_normal.

        ENDLOOP.

        IF lt_normal IS NOT INITIAL.

          SORT lt_normal BY id_no supplier company_code fiscal_year.

          DATA: lt_group     TYPE tt_invoice_details,
                lv_prev_id   TYPE zvendor_payment-id_no,
                lv_prev_supp TYPE zvendor_payment-supplier,
                lv_prev_cc   TYPE zvendor_payment-company_code,
                lv_prev_fy   TYPE zvendor_payment-fiscal_year,
                lv_first     TYPE abap_bool VALUE abap_true.

          LOOP AT lt_normal INTO DATA(ls_norm).

            IF lv_first = abap_false
               AND ( ls_norm-id_no        <> lv_prev_id
                  OR ls_norm-supplier     <> lv_prev_supp
                  OR ls_norm-company_code <> lv_prev_cc
                  OR ls_norm-fiscal_year  <> lv_prev_fy ).

              TRY.
                  DATA(cid_g) = to_upper( cl_uuid_factory=>create_system_uuid( )->create_uuid_x16( ) ).
                CATCH cx_uuid_error.
                  cid_g = ''.
              ENDTRY.

              IF cid_g IS INITIAL.
                lv_fail_count = lv_fail_count + lines( lt_group ).
                LOOP AT lt_group INTO DATA(ls_gm).
                  lv_messages = lv_messages && |JournalEntry { ls_gm-journal_entry } (ID { ls_gm-id_no }): Error - Unable to generate a unique posting reference. |.
                ENDLOOP.
              ELSE.
                DATA(lv_gres) = postGroupedInvoiceData(
                                  it_group        = lt_group
                                  c_id            = cid_g
                                  iv_posting_date = lv_posting_date ).

                IF lv_gres CS 'Successfully'
                   AND lv_gres NS 'Failed' AND lv_gres NS 'failed'
                   AND lv_gres NS 'Error'  AND lv_gres NS 'error'.
                  lv_success_count = lv_success_count + lines( lt_group ).
                ELSE.
                  lv_fail_count = lv_fail_count + lines( lt_group ).
                ENDIF.
                lv_messages = lv_messages && |ID { lv_prev_id } / Vendor { lv_prev_supp } ({ lines( lt_group ) } payment(s)): { lv_gres } |.
              ENDIF.

              CLEAR lt_group.
            ENDIF.

            APPEND ls_norm TO lt_group.
            lv_prev_id   = ls_norm-id_no.
            lv_prev_supp = ls_norm-supplier.
            lv_prev_cc   = ls_norm-company_code.
            lv_prev_fy   = ls_norm-fiscal_year.
            lv_first     = abap_false.

          ENDLOOP.

          IF lt_group IS NOT INITIAL.
            TRY.
                DATA(cid_l) = to_upper( cl_uuid_factory=>create_system_uuid( )->create_uuid_x16( ) ).
              CATCH cx_uuid_error.
                cid_l = ''.
            ENDTRY.

            IF cid_l IS INITIAL.
              lv_fail_count = lv_fail_count + lines( lt_group ).
              LOOP AT lt_group INTO DATA(ls_gm2).
                lv_messages = lv_messages && |JournalEntry { ls_gm2-journal_entry } (ID { ls_gm2-id_no }): Error - Unable to generate a unique posting reference. |.
              ENDLOOP.
            ELSE.
              DATA(lv_gres2) = postGroupedInvoiceData(
                                 it_group        = lt_group
                                 c_id            = cid_l
                                 iv_posting_date = lv_posting_date ).

              IF lv_gres2 CS 'Successfully'
                 AND lv_gres2 NS 'Failed' AND lv_gres2 NS 'failed'
                 AND lv_gres2 NS 'Error'  AND lv_gres2 NS 'error'.
                lv_success_count = lv_success_count + lines( lt_group ).
              ELSE.
                lv_fail_count = lv_fail_count + lines( lt_group ).
              ENDIF.
              lv_messages = lv_messages && |ID { lv_prev_id } / Vendor { lv_prev_supp } ({ lines( lt_group ) } payment(s)): { lv_gres2 } |.
            ENDIF.
          ENDIF.

        ENDIF.

        message = |Processed: { lv_success_count } succeeded, { lv_fail_count } failed. { lv_messages }|.

      CATCH cx_sy_open_sql_db INTO DATA(lx_sql).
        DATA(lv_sql_reason) = clean_message_text( lx_sql->get_text( ) ).
        IF lv_sql_reason IS INITIAL.
          lv_sql_reason = |Database is temporarily unavailable.|.
        ENDIF.
        message = |Posting could not be completed due to a database issue. Reason: { lv_sql_reason }|.

      CATCH cx_root INTO DATA(lx_root).
        DATA(lv_root_reason) = clean_message_text( lx_root->get_text( ) ).
        IF lv_root_reason IS INITIAL.
          lv_root_reason = |An unexpected issue occurred while processing the request.|.
        ENDIF.
        message = |Posting could not be completed. Reason: { lv_root_reason }|.

    ENDTRY.

  ENDMETHOD.


  METHOD reverse_journal_entry.

    DATA: lt_jr           TYPE TABLE FOR ACTION IMPORT i_journalentrytp~reverse,
          lv_rev_doc      TYPE string,
          lv_rev_fy       TYPE i_journalentrytp-fiscalyear,
          lv_rev_cc       TYPE i_journalentrytp-companycode,
          lv_existing_err TYPE string,
          lv_final_err    TYPE string.

    DATA(lv_uname) = cl_abap_context_info=>get_user_technical_name( ).

    APPEND INITIAL LINE TO lt_jr ASSIGNING FIELD-SYMBOL(<jr>).

    <jr>-companycode        = iv_company_code.
    <jr>-fiscalyear         = iv_fiscal_year.
    <jr>-accountingdocument = |{ iv_journal_entry ALPHA = IN }|.
    <jr>-%param = VALUE #(
      postingdate    = cl_abap_context_info=>get_system_date( )
      reversalreason = 'AR'
      createdbyuser  = lv_uname
    ).

    MODIFY ENTITIES OF i_journalentrytp PRIVILEGED
      ENTITY journalentry
      EXECUTE reverse FROM lt_jr
      FAILED   DATA(ls_failed)
      REPORTED DATA(ls_reported)
      MAPPED   DATA(ls_mapped).

    IF ls_failed-journalentry IS NOT INITIAL.
      LOOP AT ls_reported-journalentry ASSIGNING FIELD-SYMBOL(<ls_rep>).
        IF <ls_rep>-%msg IS BOUND.
          rv_message = rv_message && <ls_rep>-%msg->if_message~get_text( ) && | |.
        ENDIF.
      ENDLOOP.
      rv_message = clean_message_text( rv_message ).
      IF rv_message IS INITIAL.
        rv_message = |The system did not return a specific reason for the reversal failure.|.
      ENDIF.
      rv_message = |Reversal Failed for JE { iv_journal_entry }: { rv_message }|.

      SELECT SINGLE postingerror
            FROM zvendor_payment
            WHERE journal_entry = @iv_journal_entry
              AND company_code  = @iv_company_code
              AND fiscal_year   = @iv_fiscal_year
            INTO @lv_existing_err.

      IF lv_existing_err IS NOT INITIAL.
        lv_final_err = |{ lv_existing_err } | && rv_message.
      ELSE.
        lv_final_err = rv_message.
      ENDIF.
      lv_final_err = clean_message_text( lv_final_err ).

      UPDATE zvendor_payment
        SET postingerror = @lv_final_err
        WHERE journal_entry = @iv_journal_entry
          AND company_code  = @iv_company_code
          AND fiscal_year   = @iv_fiscal_year.
      COMMIT WORK AND WAIT.

      RETURN.

    ENDIF.

    COMMIT ENTITIES
      RESPONSE OF i_journalentrytp
      FAILED   DATA(lt_commit_failed)
      REPORTED DATA(lt_commit_reported).

    IF lt_commit_failed IS NOT INITIAL.
      LOOP AT lt_commit_failed-journalentry ASSIGNING FIELD-SYMBOL(<ls_cf>).
        rv_message = rv_message && CONV string( <ls_cf>-%fail-cause ) && | |.
      ENDLOOP.
      LOOP AT lt_commit_reported-journalentry ASSIGNING FIELD-SYMBOL(<ls_crep>).
        IF <ls_crep>-%msg IS BOUND.
          rv_message = rv_message && <ls_crep>-%msg->if_message~get_text( ) && | |.
        ENDIF.
      ENDLOOP.
      rv_message = clean_message_text( rv_message ).
      IF rv_message IS INITIAL.
        rv_message = |The system did not return a specific reason for the reversal commit failure.|.
      ENDIF.
      rv_message = |Reversal Commit Failed for JE { iv_journal_entry }: { rv_message }|.

      SELECT SINGLE postingerror
         FROM zvendor_payment
         WHERE journal_entry = @iv_journal_entry
           AND company_code  = @iv_company_code
           AND fiscal_year   = @iv_fiscal_year
         INTO @lv_existing_err.

      IF lv_existing_err IS NOT INITIAL.
        lv_final_err = |{ lv_existing_err } | && rv_message.
      ELSE.
        lv_final_err = rv_message.
      ENDIF.
      lv_final_err = clean_message_text( lv_final_err ).

      UPDATE zvendor_payment
        SET postingerror = @lv_final_err
        WHERE journal_entry = @iv_journal_entry
          AND company_code  = @iv_company_code
          AND fiscal_year   = @iv_fiscal_year.
      COMMIT WORK AND WAIT.

      RETURN.
    ENDIF.


    LOOP AT lt_commit_reported-journalentry ASSIGNING FIELD-SYMBOL(<ls_crep_ok>).
      lv_rev_cc  = <ls_crep_ok>-CompanyCode.
      lv_rev_fy  = <ls_crep_ok>-FiscalYear.
      lv_rev_doc = <ls_crep_ok>-AccountingDocument.
      EXIT.
    ENDLOOP.

    IF lv_rev_doc IS NOT INITIAL.
      rv_message = |Reversal Document { lv_rev_doc } (FY { lv_rev_fy }, CC { lv_rev_cc }) | &&
                   |posted Successfully for original JE { iv_journal_entry }|.
    ELSE.
      rv_message = |Reversal Done Successfully for JE { iv_journal_entry } (no doc number captured)|.
    ENDIF.

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

    DO 100 TIMES.
      IF rv_clean NS '  '.
        EXIT.
      ENDIF.
      REPLACE ALL OCCURRENCES OF '  ' IN rv_clean WITH ` `.
    ENDDO.

    CONDENSE rv_clean.

    IF strlen( rv_clean ) > 500.
      lv_tmp = rv_clean(497).
      rv_clean = |{ lv_tmp }...|.
    ENDIF.
  ENDMETHOD.


  METHOD postGroupedInvoiceData.
    DATA: lt_je_deep    TYPE TABLE FOR ACTION IMPORT i_journalentrytp~post,
          document      TYPE string,
          lv_error_text TYPE string.

    DATA(lv_uname) = cl_abap_context_info=>get_user_technical_name( ).

    IF it_group IS INITIAL.
      message = |No group data provided.|.
      RETURN.
    ENDIF.

    DATA(ls_head) = it_group[ 1 ].

    " Total sum of all AP amounts in the group
    DATA lv_total TYPE zvendor_payment-amount_proposal.
    lv_total = 0.
    LOOP AT it_group INTO DATA(ls_sum).
      lv_total = lv_total + ls_sum-amount_proposal.
    ENDLOOP.

    " Bank profit center for header line's house bank
    SELECT SINGLE FROM zbankproficenter AS a
      FIELDS a~house_bank , a~profit_center
      WHERE a~house_bank   = @ls_head-house_bank
        AND a~company_code = @ls_head-company_code
      INTO @DATA(ProfitCenter).

    APPEND INITIAL LINE TO lt_je_deep ASSIGNING FIELD-SYMBOL(<je_deep>).

    <je_deep>-%cid   = c_id.
    <je_deep>-%param = VALUE #(
      companycode                  = ls_head-company_code
      businesstransactiontype      = 'RFPO'
      DocumentReferenceID          = ls_head-transactionid
      accountingdocumenttype       = 'ZP'
      AccountingDocumentHeaderText = ls_head-utrnumber
      CreatedByUser                = lv_uname
      documentdate                 = iv_posting_date
      postingdate                  = iv_posting_date
    ).

    DATA lv_item_no TYPE i VALUE 2.
    DATA lv_item_ch TYPE c LENGTH 3.


 <je_deep>-%param-_apitems = VALUE #(
      ( glaccountlineitem   = |002|
        Supplier            = |{ ls_head-supplier ALPHA = IN }|
        BusinessPlace       = ls_head-business_place
        DocumentItemText    = ls_head-utrnumber
        AssignmentReference = ls_head-transactionid
        PaymentReference    = ls_head-utrnumber
        _currencyamount     = VALUE #(
          ( currencyrole           = '00'
            journalentryitemamount = lv_total
            currency               = 'INR' ) ) ) ).

    <je_deep>-%param-_glitems = VALUE #(
      ( glaccountlineitem   = |001|
        glaccount           = ls_head-gl_account
        HouseBank           = ls_head-house_bank
        HouseBankAccount    = ls_head-house_bank_account
        AssignmentReference = ls_head-transactionid
        ProfitCenter        = ProfitCenter-profit_center
        DocumentItemText    = ls_head-utrnumber
        _currencyamount     = VALUE #(
          ( currencyrole           = '00'
            JournalEntryItemAmount = lv_total * -1
            currency               = 'INR' ) ) )
    ).

    MODIFY ENTITIES OF i_journalentrytp PRIVILEGED
      ENTITY journalentry
      EXECUTE post FROM lt_je_deep
      FAILED   DATA(ls_failed_deep)
      REPORTED DATA(ls_reported_deep)
      MAPPED   DATA(ls_mapped_deep).

    IF ls_failed_deep IS NOT INITIAL.
      CLEAR lv_error_text.
      LOOP AT ls_reported_deep-journalentry ASSIGNING FIELD-SYMBOL(<ls_rep>).
        IF <ls_rep>-%msg IS BOUND.
          lv_error_text = lv_error_text && <ls_rep>-%msg->if_message~get_text( ) && | |.
        ENDIF.
      ENDLOOP.
      lv_error_text = clean_message_text( lv_error_text ).
      IF lv_error_text IS INITIAL.
        lv_error_text = |The system did not return a specific reason for the failure.|.
      ENDIF.

      LOOP AT it_group INTO DATA(ls_ef).
        UPDATE zvendor_payment
          SET postingerror = @lv_error_text
          WHERE id_no         = @ls_ef-id_no
            AND journal_entry = @ls_ef-journal_entry
            AND company_code  = @ls_ef-company_code
            AND fiscal_year   = @ls_ef-fiscal_year.
      ENDLOOP.
      COMMIT WORK AND WAIT.

      message = |Vendor { ls_head-supplier } group failed in posting. Check error in report and return.|.
      RETURN.
    ENDIF.

    COMMIT ENTITIES
      RESPONSE OF i_journalentrytp
      FAILED   DATA(lt_commit_failed)
      REPORTED DATA(lt_commit_reported).

    IF lt_commit_failed IS NOT INITIAL.
      CLEAR lv_error_text.
      LOOP AT lt_commit_failed-journalentry ASSIGNING FIELD-SYMBOL(<ls_cfailed>).
        lv_error_text = lv_error_text && CONV string( <ls_cfailed>-%fail-cause ) && | |.
      ENDLOOP.
      LOOP AT lt_commit_reported-journalentry ASSIGNING FIELD-SYMBOL(<ls_crep_nrm>).
        IF <ls_crep_nrm>-%msg IS BOUND.
          lv_error_text = lv_error_text && <ls_crep_nrm>-%msg->if_message~get_text( ) && | |.
        ENDIF.
      ENDLOOP.
      lv_error_text = clean_message_text( lv_error_text ).
      IF lv_error_text IS INITIAL.
        lv_error_text = |The system did not return a specific reason for the commit failure.|.
      ENDIF.

      LOOP AT it_group INTO DATA(ls_ecf).
        UPDATE zvendor_payment
          SET postingerror = @lv_error_text
          WHERE id_no         = @ls_ecf-id_no
            AND journal_entry = @ls_ecf-journal_entry
            AND company_code  = @ls_ecf-company_code
            AND fiscal_year   = @ls_ecf-fiscal_year.
      ENDLOOP.
      COMMIT WORK AND WAIT.

      message = |Vendor { ls_head-supplier } group failed in posting. Check error in report and return.|.
      RETURN.
    ENDIF.

    LOOP AT lt_commit_reported-journalentry ASSIGNING FIELD-SYMBOL(<ls_reported>).
      document = <ls_reported>-AccountingDocument.
    ENDLOOP.

    IF document IS INITIAL.
      lv_error_text = |The system did not return a document number after posting. Please verify in SAP.|.

      LOOP AT it_group INTO DATA(ls_end).
        UPDATE zvendor_payment
          SET postingerror = @lv_error_text
          WHERE id_no         = @ls_end-id_no
            AND journal_entry = @ls_end-journal_entry
            AND company_code  = @ls_end-company_code
            AND fiscal_year   = @ls_end-fiscal_year.
      ENDLOOP.
      COMMIT WORK AND WAIT.

      message = |Vendor { ls_head-supplier } group failed in posting. Check error in report and return.|.
      RETURN.
    ENDIF.

    LOOP AT it_group INTO DATA(ls_ok).
      UPDATE zvendor_payment
        SET post_status     = 'POSTED',
            postingdocument = @document,
            postingerror    = @space
        WHERE id_no         = @ls_ok-id_no
          AND journal_entry = @ls_ok-journal_entry
          AND company_code  = @ls_ok-company_code
          AND fiscal_year   = @ls_ok-fiscal_year.
    ENDLOOP.
    COMMIT WORK AND WAIT.

    message = |Document { document } Posted Successfully for { lines( it_group ) } payment(s)|.

  ENDMETHOD.


  METHOD postInvoiceData.
    DATA: lt_je_deep    TYPE TABLE FOR ACTION IMPORT i_journalentrytp~post,
          document      TYPE string,
          lv_error_text TYPE string.
    DATA: lv_today      TYPE d,
          specialGLCode TYPE c LENGTH 1.

    lv_today = cl_abap_context_info=>get_system_date( ).
    DATA(lv_uname) = cl_abap_context_info=>get_user_technical_name( ).

    SELECT SINGLE FROM zbankproficenter AS a
    FIELDS a~house_bank , a~profit_center
    WHERE a~house_bank =  @wa_data-house_bank
    AND a~company_code = @wa_data-company_code
    INTO @DATA(BankProfitCenter).

    IF wa_data-specialglcode = 'F'.

      IF wa_data-supplier CP '5*'.
        specialGLCode = 'K'.
      ELSE.
        specialglcode = 'A'.
      ENDIF.

      APPEND INITIAL LINE TO lt_je_deep ASSIGNING FIELD-SYMBOL(<je_deep>).

      <je_deep>-%cid   = c_id.
      <je_deep>-%param = VALUE #(
        companycode                  = wa_data-company_code
        businesstransactiontype      = 'RFBU'
        DocumentReferenceID          = wa_data-transactionid
        accountingdocumenttype       = 'ZP'
        AccountingDocumentHeaderText  = wa_data-utrnumber
        CreatedByUser                = lv_uname
        documentdate                 = iv_posting_date
        postingdate                  = iv_posting_date

        _apitems = VALUE #(
          ( glaccountlineitem = |002|
            Supplier          = |{ wa_data-supplier ALPHA = IN }|
            BusinessPlace     = wa_data-business_place
            DocumentItemText  = wa_data-utrnumber
            SpecialGLCode     = specialGLCode
            AssignmentReference = lv_assignmentrefadv
            _currencyamount   = VALUE #(
              ( currencyrole           = '00'
                journalentryitemamount = wa_data-amount_proposal
                currency               = 'INR' ) ) ) )

        _glitems = VALUE #(
          ( glaccountlineitem   = |001|
            glaccount           = wa_data-gl_account
            HouseBank           = wa_data-house_bank
            HouseBankAccount    = wa_data-house_bank_account
            AssignmentReference = wa_data-transactionid
            ProfitCenter        = BankProfitCenter-profit_center
            DocumentItemText    = wa_data-utrnumber
            _currencyamount     = VALUE #(
              ( currencyrole           = '00'
                JournalEntryItemAmount = wa_data-amount_proposal * -1
                currency               = 'INR' ) ) ) )
      ).

      MODIFY ENTITIES OF i_journalentrytp PRIVILEGED
        ENTITY journalentry
        EXECUTE post FROM lt_je_deep
        FAILED   DATA(ls_failed_deep)
        REPORTED DATA(ls_reported_deep)
        MAPPED   DATA(ls_mapped_deep).

      IF ls_failed_deep IS NOT INITIAL.
        CLEAR lv_error_text.
        LOOP AT ls_reported_deep-journalentry ASSIGNING FIELD-SYMBOL(<ls_rep>).
          IF <ls_rep>-%msg IS BOUND.
            lv_error_text = lv_error_text && <ls_rep>-%msg->if_message~get_text( ) && | |.
          ENDIF.
        ENDLOOP.
        lv_error_text = clean_message_text( lv_error_text ).
        IF lv_error_text IS INITIAL.
          lv_error_text = |The system did not return a specific reason for the failure.|.
        ENDIF.

        UPDATE zvendor_payment
          SET postingerror = @lv_error_text
          WHERE id_no         = @wa_data-id_no
            AND journal_entry = @wa_data-journal_entry
            AND company_code  = @wa_data-company_code
            AND fiscal_year   = @wa_data-fiscal_year.
        COMMIT WORK AND WAIT.

        message = |Document { wa_data-journal_entry } failed in posting. Check error in report and return.|.
        RETURN.
      ENDIF.

      COMMIT ENTITIES
        RESPONSE OF i_journalentrytp
        FAILED   DATA(lt_commit_failed)
        REPORTED DATA(lt_commit_reported).

      IF lt_commit_failed IS NOT INITIAL.
        CLEAR lv_error_text.
        LOOP AT lt_commit_failed-journalentry ASSIGNING FIELD-SYMBOL(<ls_cfailed>).
          lv_error_text = lv_error_text && CONV string( <ls_cfailed>-%fail-cause ) && | |.
        ENDLOOP.
        LOOP AT lt_commit_reported-journalentry ASSIGNING FIELD-SYMBOL(<ls_crep_adv>).
          IF <ls_crep_adv>-%msg IS BOUND.
            lv_error_text = lv_error_text && <ls_crep_adv>-%msg->if_message~get_text( ) && | |.
          ENDIF.
        ENDLOOP.
        lv_error_text = clean_message_text( lv_error_text ).
        IF lv_error_text IS INITIAL.
          lv_error_text = |The system did not return a specific reason for the commit failure.|.
        ENDIF.
        UPDATE zvendor_payment
                 SET postingerror = @lv_error_text
                 WHERE id_no         = @wa_data-id_no
                   AND journal_entry = @wa_data-journal_entry
                   AND company_code  = @wa_data-company_code
                   AND fiscal_year   = @wa_data-fiscal_year.
        COMMIT WORK AND WAIT.

        message = |Document { wa_data-journal_entry } failed in posting. Check error in report and return.|.
        RETURN.
      ENDIF.

      LOOP AT lt_commit_reported-journalentry ASSIGNING FIELD-SYMBOL(<ls_reported>).
        document = <ls_reported>-AccountingDocument.
      ENDLOOP.

      IF document IS NOT INITIAL.

        UPDATE zvendor_payment
        SET post_status     = 'POSTED',
            postingdocument = @document
        WHERE id_no         = @wa_data-id_no
          AND journal_entry = @wa_data-journal_entry
          AND fiscal_year  = @wa_data-fiscal_year
          AND company_code = @wa_data-company_code.
        COMMIT WORK AND WAIT.

        DATA(lv_reversal_msg) = reverse_journal_entry(
          iv_journal_entry = wa_data-journal_entry
          iv_fiscal_year   = wa_data-fiscal_year
          iv_company_code  = wa_data-company_code ).

        IF lv_reversal_msg CS 'Successfully'.
          message = |Advance Payment Successful: Document { document } posted. Reversal: { lv_reversal_msg }|.
        ELSE.
          message = |Document { document } advance invoice failed in reversing. Check error in report and return.|.
        ENDIF.

        RETURN.

      ELSE.
        lv_error_text = |The system did not return a document number after posting. Please verify in SAP.|.

        UPDATE zvendor_payment
          SET postingerror = @lv_error_text
          WHERE id_no         = @wa_data-id_no
            AND journal_entry = @wa_data-journal_entry
            AND company_code  = @wa_data-company_code
            AND fiscal_year   = @wa_data-fiscal_year.
        COMMIT WORK AND WAIT.

        message = |Document { wa_data-journal_entry } failed in posting. Check error in report and return.|.
        RETURN.
      ENDIF.

    ELSE.

      SELECT SINGLE FROM zbankproficenter AS a
   FIELDS a~house_bank , a~profit_center
   WHERE a~house_bank =  @wa_data-house_bank
   AND a~company_code = @wa_data-company_code
   INTO @DATA(ProfitCenter).

      SELECT FROM I_JournalEntryItem AS a
        FIELDS *
        WHERE a~AccountingDocument   = @wa_data-journal_entry
          AND a~CompanyCode          = @wa_data-company_code
          AND a~FiscalYear           = @wa_data-fiscal_year
          AND a~FinancialAccountType = 'K'
          AND a~Ledger               = '0L'
        INTO TABLE @DATA(ValidateAdvance).

      DATA: lv_inv_ref TYPE string.

      lv_inv_ref = lv_inv_ref_doc.

      IF lines( ValidateAdvance ) > 1.
        CLEAR lv_inv_ref.
      ENDIF.

      APPEND INITIAL LINE TO lt_je_deep ASSIGNING <je_deep>.

      <je_deep>-%cid   = c_id.
      <je_deep>-%param = VALUE #(
        companycode                  = wa_data-company_code
        businesstransactiontype      = 'RFPO'
        DocumentReferenceID          = wa_data-transactionid
        InvoiceReferenceDocument     = lv_inv_ref
        accountingdocumenttype       = 'ZP'
        AccountingDocumentHeaderText = wa_data-utrnumber
        CreatedByUser                = lv_uname
        documentdate                 = iv_posting_date
        postingdate                  = iv_posting_date

        _apitems = VALUE #(
          ( glaccountlineitem = |002|
            Supplier          = |{ wa_data-supplier ALPHA = IN }|
            BusinessPlace     = wa_data-business_place
            DocumentItemText  = wa_data-utrnumber
            AssignmentReference = wa_data-transactionid
            PaymentReference = wa_data-utrnumber
            _currencyamount   = VALUE #(
              ( currencyrole           = '00'
                journalentryitemamount = wa_data-amount_proposal
                currency               = 'INR' ) ) ) )

        _glitems = VALUE #(
          ( glaccountlineitem   = |001|
            glaccount           = wa_data-gl_account
            HouseBank           = wa_data-house_bank
            HouseBankAccount    = wa_data-house_bank_account
            AssignmentReference = wa_data-transactionid
            ProfitCenter        = ProfitCenter-profit_center
            DocumentItemText    = wa_data-utrnumber
            _currencyamount     = VALUE #(
              ( currencyrole           = '00'
                JournalEntryItemAmount = wa_data-amount_proposal * -1
                currency               = 'INR' ) ) ) )
      ).

      MODIFY ENTITIES OF i_journalentrytp PRIVILEGED
        ENTITY journalentry
        EXECUTE post FROM lt_je_deep
        FAILED   ls_failed_deep
        REPORTED ls_reported_deep
        MAPPED   ls_mapped_deep.

      IF ls_failed_deep IS NOT INITIAL.
        CLEAR lv_error_text.
        LOOP AT ls_reported_deep-journalentry ASSIGNING <ls_rep>.
          IF <ls_rep>-%msg IS BOUND.
            lv_error_text = lv_error_text && <ls_rep>-%msg->if_message~get_text( ) && | |.
          ENDIF.
        ENDLOOP.
        lv_error_text = clean_message_text( lv_error_text ).
        IF lv_error_text IS INITIAL.
          lv_error_text = |The system did not return a specific reason for the failure.|.
        ENDIF.

        UPDATE zvendor_payment
          SET postingerror = @lv_error_text
          WHERE id_no         = @wa_data-id_no
            AND journal_entry = @wa_data-journal_entry
            AND company_code  = @wa_data-company_code
            AND fiscal_year   = @wa_data-fiscal_year.
        COMMIT WORK AND WAIT.

        message = |Document { wa_data-journal_entry } failed in posting. Check error in report and return.|.
        RETURN.
      ENDIF.

      COMMIT ENTITIES
        RESPONSE OF i_journalentrytp
        FAILED   lt_commit_failed
        REPORTED lt_commit_reported.

      IF lt_commit_failed IS NOT INITIAL.
        CLEAR lv_error_text.
        LOOP AT lt_commit_failed-journalentry ASSIGNING <ls_cfailed>.
          lv_error_text = lv_error_text && CONV string( <ls_cfailed>-%fail-cause ) && | |.
        ENDLOOP.
        LOOP AT lt_commit_reported-journalentry ASSIGNING FIELD-SYMBOL(<ls_crep_nrm>).
          IF <ls_crep_nrm>-%msg IS BOUND.
            lv_error_text = lv_error_text && <ls_crep_nrm>-%msg->if_message~get_text( ) && | |.
          ENDIF.
        ENDLOOP.
        lv_error_text = clean_message_text( lv_error_text ).
        IF lv_error_text IS INITIAL.
          lv_error_text = |The system did not return a specific reason for the commit failure.|.
        ENDIF.

        UPDATE zvendor_payment
          SET postingerror = @lv_error_text
          WHERE id_no         = @wa_data-id_no
            AND journal_entry = @wa_data-journal_entry
            AND company_code  = @wa_data-company_code
            AND fiscal_year   = @wa_data-fiscal_year.
        COMMIT WORK AND WAIT.

        message = |Document { wa_data-journal_entry } failed in posting. Check error in report and return.|.
        RETURN.
      ENDIF.

      LOOP AT lt_commit_reported-journalentry ASSIGNING <ls_reported>.
        document = <ls_reported>-AccountingDocument.
      ENDLOOP.

      IF document IS INITIAL.
        lv_error_text = |The system did not return a document number after posting. Please verify in SAP.|.

        UPDATE zvendor_payment
          SET postingerror = @lv_error_text
          WHERE id_no         = @wa_data-id_no
            AND journal_entry = @wa_data-journal_entry
            AND company_code  = @wa_data-company_code
            AND fiscal_year   = @wa_data-fiscal_year.
        COMMIT WORK AND WAIT.

        message = |Document { wa_data-journal_entry } failed in posting. Check error in report and return.|.
        RETURN.
      ENDIF.

      UPDATE zvendor_payment
        SET post_status     = 'POSTED',
            postingdocument = @document,
            postingerror    = @space
        WHERE id_no         = @wa_data-id_no
          AND journal_entry = @wa_data-journal_entry
          AND company_code  = @wa_data-company_code
          AND fiscal_year   = @wa_data-fiscal_year.
      COMMIT WORK AND WAIT.

      message = |Document { document } Posted Successfully|.
      RETURN.

    ENDIF.

    CLEAR lt_je_deep.

  ENDMETHOD.
ENDCLASS.
