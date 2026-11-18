CLASS zcl_http_payment_inquiry DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_service_extension.

  PRIVATE SECTION.

    CONSTANTS c_gcif             TYPE string VALUE 'CBXMGRT4'.
    CONSTANTS c_login_id         TYPE string VALUE 'APIUSER@CBXMGRT4'.
    CONSTANTS c_status_accepted  TYPE string VALUE 'Accepted'.
    CONSTANTS c_content_type     TYPE string VALUE 'application/json'.
    CONSTANTS c_body_max_len     TYPE i      VALUE 2000.

    TYPES: BEGIN OF ty_txn_record,
             reference_no     TYPE string,
             status           TYPE string,
             txn_status       TYPE string,
             od_status_desc   TYPE string,
             od_reject_reason TYPE string,
             paymentrefno     TYPE string,
             utr_no           TYPE string,
             txn_reference_no TYPE string,
           END OF ty_txn_record.
    TYPES tt_txn_records TYPE STANDARD TABLE OF ty_txn_record WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_api_response,
             all_records TYPE tt_txn_records,
           END OF ty_api_response.

    "==== NEW: Yes Bank inquiry response structures (CC2000) ====
    TYPES: BEGIN OF ty_yb_initiation,
             endtoendidentification    TYPE string,
             instructionidentification TYPE string,
           END OF ty_yb_initiation,
           BEGIN OF ty_yb_data,
             status                    TYPE string,
             transactionidentification TYPE string,
             consentid                 TYPE string,
             initiation                TYPE ty_yb_initiation,
           END OF ty_yb_data,
           BEGIN OF ty_yb_response,
             data TYPE ty_yb_data,
           END OF ty_yb_response.

    TYPES: BEGIN OF ty_api_result,
             body      TYPE string,
             http_code TYPE i,
             is_ok     TYPE abap_bool,
             error_msg TYPE string,
           END OF ty_api_result.

    TYPES: BEGIN OF ty_txn_result,
             transaction_id TYPE string,
             payment_status TYPE string,
             journal_entry  TYPE string,
             utr_number     TYPE string,
             id_no          TYPE string,
             outcome        TYPE string,
             message        TYPE string,
             http_code      TYPE i,
           END OF ty_txn_result.
    TYPES tt_txn_results TYPE STANDARD TABLE OF ty_txn_result WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_final_response,
             run_date      TYPE string,
             total         TYPE i,
             success_count TYPE i,
             error_count   TYPE i,
             skipped_count TYPE i,
             results       TYPE tt_txn_results,
           END OF ty_final_response.

    TYPES: BEGIN OF ty_item,
             DbKey         TYPE string,
             idno          TYPE string,
             JournalEntry  TYPE string,
             FiscleYear    TYPE string,
             CompanyCode   TYPE string,
             Supplier      TYPE string,
             SupplierName  TYPE string,
             HouseBank     TYPE string,
             InvoiceAmount TYPE string,
             Amount        TYPE string,
             Currency      TYPE string,
             TransactionId TYPE string,
             PaymentStatus TYPE string,
             utrnumber     TYPE string,
           END OF ty_item,
           ty_items TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY,

           BEGIN OF ty_payload,
             action TYPE string,
             items  TYPE ty_items,
           END OF ty_payload.

    METHODS process_inquiry
      IMPORTING it_items           TYPE ty_items
                iv_date            TYPE d
      RETURNING VALUE(rs_response) TYPE ty_final_response.

    METHODS call_cpi_api
      IMPORTING iv_payload       TYPE string
      RETURNING VALUE(rs_result) TYPE ty_api_result.

    "==== NEW: Yes Bank inquiry call (CC2000) ====
    METHODS call_yesbank_api
      IMPORTING iv_payload       TYPE string
      RETURNING VALUE(rs_result) TYPE ty_api_result.

    METHODS build_payload
      IMPORTING iv_ref_no      TYPE clike
                iv_date        TYPE d
      RETURNING VALUE(rv_json) TYPE string.

    "==== NEW: Yes Bank inquiry payload (CC2000) ====
    METHODS build_yesbank_payload
      IMPORTING iv_ref_no      TYPE clike
      RETURNING VALUE(rv_json) TYPE string.

    METHODS update_success
      IMPORTING iv_txn_id        TYPE clike
                iv_idno          TYPE clike
                iv_journal_alpha TYPE clike
                lv_journal       type clike
                iv_companycode   TYPE clike
                iv_fiscalyear    TYPE clike
                iv_utr           TYPE string
                iv_status        TYPE string
      RETURNING VALUE(rv_error)  TYPE string.

    METHODS write_log
      IMPORTING iv_txn_id        TYPE clike
                iv_idno          TYPE clike OPTIONAL
                iv_journal_alpha TYPE clike
                lv_journal       type clike
                iv_companycode   TYPE clike OPTIONAL
                iv_fiscalyear    TYPE clike OPTIONAL
                iv_utr           TYPE string
                iv_status        TYPE string
                iv_error         TYPE string
                iv_body          TYPE string
                iv_http_code     TYPE i.

ENDCLASS.



CLASS ZCL_HTTP_PAYMENT_INQUIRY IMPLEMENTATION.


  METHOD if_http_service_extension~handle_request.

    DATA lv_body    TYPE string.
    DATA ls_payload TYPE ty_payload.

    lv_body = request->get_text( ).

    TRY.
        /ui2/cl_json=>deserialize(
          EXPORTING json        = lv_body
                    pretty_name = /ui2/cl_json=>pretty_mode-camel_case
          CHANGING  data        = ls_payload ).
      CATCH cx_root INTO DATA(lx_parse).
        response->set_status( i_code = 400 i_reason = 'Bad Request' ).
        response->set_text( |JSON parse error: { lx_parse->get_text( ) }| ).
        RETURN.
    ENDTRY.

    IF ls_payload-items IS INITIAL.
      response->set_status( i_code = 400 i_reason = 'Bad Request' ).
      response->set_text( 'No items received in payload' ).
      RETURN.
    ENDIF.

    DATA(ls_response) = process_inquiry(
                          it_items = ls_payload-items
                          iv_date  = sy-datum ).

    DATA lv_json TYPE string.
    /ui2/cl_json=>serialize(
      EXPORTING data        = ls_response
                pretty_name = /ui2/cl_json=>pretty_mode-low_case
                compress    = abap_false
      RECEIVING r_json      = lv_json ).

    response->set_status( i_code = 200 i_reason = 'OK' ).
    response->set_header_field( i_name = 'Content-Type'                i_value = 'application/json' ).
    response->set_header_field( i_name = 'Access-Control-Allow-Origin' i_value = '*' ).
    response->set_text( lv_json ).

  ENDMETHOD.


  METHOD process_inquiry.

    DATA ls_result   TYPE ty_txn_result.
    DATA ls_api_resp TYPE ty_api_response.

    rs_response-run_date = |{ iv_date(4) }-{ iv_date+4(2) }-{ iv_date+6(2) }|.
    rs_response-total    = lines( it_items ).

    "==================================================================
    " Distinct TransactionId nikaalo. Same vendor payment ke saare
    " invoices ka same transactionid hota hai -> ek txnid = ek group.
    " Empty txnid wali lines ko alag handle karenge (grouping ke bahar).
    "==================================================================
    DATA lt_txnids TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    lt_txnids = VALUE #( FOR GROUPS grp OF <it> IN it_items
                         GROUP BY <it>-transactionid
                         ( grp ) ).

    LOOP AT lt_txnids ASSIGNING FIELD-SYMBOL(<lv_txnid>).

      CLEAR ls_result.
      CLEAR ls_api_resp.

      "---- Is txnid ke saare invoice lines ----
      DATA lt_grp TYPE ty_items.
      CLEAR lt_grp.
      LOOP AT it_items ASSIGNING FIELD-SYMBOL(<gi>) WHERE transactionid = <lv_txnid>.
        APPEND <gi> TO lt_grp.
      ENDLOOP.

      IF lt_grp IS INITIAL.
        CONTINUE.
      ENDIF.

      " Header line = group ki pehli line (checks / payload / DB keys)
      DATA(ls_head) = lt_grp[ 1 ].

" Saare journal entries ki comma-separated list (message ke liye)
      DATA lv_je_list TYPE string.
      CLEAR lv_je_list.
      LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<gl>).
        lv_je_list = COND string(
          WHEN lv_je_list IS INITIAL THEN <gl>-journalentry
          ELSE |{ lv_je_list }, { <gl>-journalentry }| ).
      ENDLOOP.

      ls_result-transaction_id = ls_head-transactionid.
      ls_result-id_no          = lv_je_list.
      ls_result-journal_entry  = ls_head-journalentry.

      DATA(lv_journal)       = CONV belnr_d( ls_head-journalentry ).
      DATA(lv_journal_alpha) = CONV belnr_d( |{ lv_journal ALPHA = IN }| ).

      "---- Empty transactionid ----
      IF ls_head-transactionid IS INITIAL.
        ls_result-outcome = 'ERROR'.
        ls_result-message = |TransactionId is empty for ID No: { lv_je_list }|.
        APPEND ls_result TO rs_response-results.
        rs_response-error_count += 1.
        CONTINUE.
      ENDIF.

      "---- UTR already exists (group me kisi bhi line pe) -> skip ----
      DATA lv_grp_utr        TYPE string.
      DATA lv_grp_pay_status TYPE string.
      CLEAR: lv_grp_utr, lv_grp_pay_status.
      LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<gu>) WHERE utrnumber IS NOT INITIAL.
        lv_grp_utr        = <gu>-utrnumber.
        lv_grp_pay_status = <gu>-paymentstatus.
        EXIT.
      ENDLOOP.

      IF lv_grp_utr IS NOT INITIAL.
        ls_result-outcome        = 'SKIPPED'.
        ls_result-utr_number     = lv_grp_utr.
        ls_result-payment_status = lv_grp_pay_status.
        ls_result-message        = |UTR already exists: { lv_grp_utr } - skipped (TxnId { ls_head-transactionid })|.
        APPEND ls_result TO rs_response-results.
        rs_response-skipped_count += 1.
        CONTINUE.
      ENDIF.

      "---- Log recovery: UTR log me hai but ZVENDOR sync nahi ----
      SELECT utrnumber, payment_status
        FROM zbank_pam_log
        WHERE transactionid  = @ls_head-transactionid
          AND utrnumber     <> @space
        ORDER BY PRIMARY KEY
        INTO @DATA(ls_log_prev)
        UP TO 1 ROWS.
      ENDSELECT.

      IF sy-subrc = 0
         AND ls_log_prev-utrnumber IS NOT INITIAL.

        UPDATE zvendor_payment
           SET utrnumber      = @ls_log_prev-utrnumber,
               payment_status = @ls_log_prev-payment_status
         WHERE transactionid = @ls_head-transactionid.

        IF sy-subrc = 0 AND sy-dbcnt > 0.
          COMMIT WORK AND WAIT.
          ls_result-outcome        = 'SUCCESS'.
          ls_result-utr_number     = ls_log_prev-utrnumber.
          ls_result-payment_status = ls_log_prev-payment_status.
          ls_result-message        = |UTR { ls_log_prev-utrnumber } recovered from log and synced to ZVENDOR_PAYMENT ({ sy-dbcnt } invoice(s)). JL No:: { lv_je_list }|.
          rs_response-success_count += 1.
        ELSE.
          ROLLBACK WORK.
          ls_result-outcome = 'ERROR'.
          ls_result-message = |UTR { ls_log_prev-utrnumber } found in log but ZVENDOR_PAYMENT sync failed (records missing / txn id mismatch). JL No:: { lv_je_list }|.
          rs_response-error_count += 1.
        ENDIF.

        APPEND ls_result TO rs_response-results.
        CONTINUE.
      ENDIF.

      "=================================================================
      "  ROUTING BY COMPANY CODE
      "  CC2000 -> Yes Bank inquiry (new). Else -> HDFC inquiry (unchanged).
      "=================================================================
      IF ls_head-companycode = '2000'.

        "================= YES BANK INQUIRY PATH (CC2000) ==============
        DATA(ls_yb_api) = call_yesbank_api(
                            build_yesbank_payload( iv_ref_no = ls_head-transactionid ) ).

        ls_result-http_code = ls_yb_api-http_code.

        IF ls_yb_api-is_ok = abap_false.
          ls_result-outcome = 'ERROR'.
          ls_result-message = |{ ls_yb_api-error_msg } (JL No:: { lv_je_list })|.
          write_log( iv_txn_id        = ls_head-transactionid
                     iv_idno          = ls_head-idno
                     iv_journal_alpha = lv_journal_alpha
                     lv_journal       = lv_journal
                     iv_companycode   = ls_head-companycode
                     iv_fiscalyear    = ls_head-fiscleyear
                     iv_utr           = ''
                     iv_status        = ''
                     iv_error         = ls_result-message
                     iv_body          = ls_yb_api-body
                     iv_http_code     = ls_yb_api-http_code ).
          APPEND ls_result TO rs_response-results.
          rs_response-error_count += 1.
          CONTINUE.
        ENDIF.

        DATA ls_yb_resp TYPE ty_yb_response.
        CLEAR ls_yb_resp.

        TRY.
            /ui2/cl_json=>deserialize(
              EXPORTING json        = ls_yb_api-body
                        pretty_name = /ui2/cl_json=>pretty_mode-low_case
              CHANGING  data        = ls_yb_resp ).
          CATCH cx_root INTO DATA(lx_yb_json).
            ls_result-outcome = 'ERROR'.
            ls_result-message = |JSON parse failed: { lx_yb_json->get_text( ) } (JL No: { lv_je_list })|.
            write_log( iv_txn_id        = ls_head-transactionid
                       iv_idno          = ls_head-idno
                       iv_journal_alpha = lv_journal_alpha
                       lv_journal       = lv_journal
                       iv_companycode   = ls_head-companycode
                       iv_fiscalyear    = ls_head-fiscleyear
                       iv_utr           = ''
                       iv_status        = ''
                       iv_error         = ls_result-message
                       iv_body          = ls_yb_api-body
                       iv_http_code     = ls_yb_api-http_code ).
            APPEND ls_result TO rs_response-results.
            rs_response-error_count += 1.
            CONTINUE.
        ENDTRY.

        ls_result-payment_status = ls_yb_resp-data-status.

        "---- UTR = EndToEndIdentification. Empty -> pending from bank ----
        DATA(lv_yb_utr) = ls_yb_resp-data-initiation-endtoendidentification.

        IF lv_yb_utr IS INITIAL.
          ls_result-outcome = 'INFO'.
          ls_result-message = |Payment is not processed till now from bank side.|
                           && | Bank Status: '{ ls_yb_resp-data-status }' (JL No:: { lv_je_list })|.
          write_log( iv_txn_id        = ls_head-transactionid
                     iv_idno          = ls_head-idno
                     iv_journal_alpha = lv_journal_alpha
                     lv_journal       = lv_journal
                     iv_companycode   = ls_head-companycode
                     iv_fiscalyear    = ls_head-fiscleyear
                     iv_utr           = ''
                     iv_status        = ls_yb_resp-data-status
                     iv_error         = ls_result-message
                     iv_body          = ls_yb_api-body
                     iv_http_code     = ls_yb_api-http_code ).
          APPEND ls_result TO rs_response-results.
          rs_response-skipped_count += 1.
          CONTINUE.
        ENDIF.

        ls_result-utr_number = lv_yb_utr.

        "---- DB update: same helper, WHERE transactionid ----
        DATA(lv_yb_db_err) = update_success(
                              iv_txn_id        = ls_head-transactionid
                              iv_idno          = ls_head-idno
                              iv_journal_alpha = lv_journal_alpha
                              lv_journal       = lv_journal
                              iv_companycode   = ls_head-companycode
                              iv_fiscalyear    = ls_head-fiscleyear
                              iv_utr           = lv_yb_utr
                              iv_status        = ls_yb_resp-data-status ).

        IF lv_yb_db_err IS INITIAL.
          ls_result-outcome = 'SUCCESS'.
          ls_result-message = |UTR { lv_yb_utr } updated for { lines( lt_grp ) } invoice(s) (source: EndToEndIdentification).|
                           && | Bank status: { ls_yb_resp-data-status }. JL No:: { lv_je_list }|.
          rs_response-success_count += 1.
        ELSE.
          ls_result-outcome = 'ERROR'.
          ls_result-message = |{ lv_yb_db_err } (JL No:: { lv_je_list })|.
          rs_response-error_count += 1.
        ENDIF.

        APPEND ls_result TO rs_response-results.
        CONTINUE.
      ENDIF.
      "================= END YES BANK INQUIRY PATH ===================

      "================= HDFC INQUIRY PATH (UNCHANGED) ===============
      "---- Single API call per distinct txnid ----
      DATA(ls_api) = call_cpi_api(
                       build_payload( iv_ref_no = ls_head-transactionid
                                      iv_date   = iv_date ) ).

      ls_result-http_code = ls_api-http_code.

      IF ls_api-is_ok = abap_false.
        ls_result-outcome = 'ERROR'.
        ls_result-message = |{ ls_api-error_msg } (JL No:: { lv_je_list })|.
        write_log( iv_txn_id        = ls_head-transactionid
                   iv_idno          = ls_head-idno
                   iv_journal_alpha = lv_journal_alpha
                   lv_journal       = lv_journal
                   iv_companycode   = ls_head-companycode
                   iv_fiscalyear    = ls_head-fiscleyear
                   iv_utr           = ''
                   iv_status        = ''
                   iv_error         = ls_result-message
                   iv_body          = ls_api-body
                   iv_http_code     = ls_api-http_code ).
        APPEND ls_result TO rs_response-results.
        rs_response-error_count += 1.
        CONTINUE.
      ENDIF.

      TRY.
          /ui2/cl_json=>deserialize(
            EXPORTING json        = ls_api-body
                      pretty_name = /ui2/cl_json=>pretty_mode-low_case
            CHANGING  data        = ls_api_resp ).
        CATCH cx_root INTO DATA(lx_json).
          ls_result-outcome = 'ERROR'.
          ls_result-message = |JSON parse failed: { lx_json->get_text( ) } (JL No: { lv_je_list })|.
          write_log( iv_txn_id        = ls_head-transactionid
                     iv_idno         = ls_head-idno
                     iv_journal_alpha = lv_journal_alpha
                     lv_journal       = lv_journal
                     iv_companycode   = ls_head-companycode
                     iv_fiscalyear    = ls_head-fiscleyear
                     iv_utr           = ''
                     iv_status        = ''
                     iv_error         = ls_result-message
                     iv_body          = ls_api-body
                     iv_http_code     = ls_api-http_code ).
          APPEND ls_result TO rs_response-results.
          rs_response-error_count += 1.
          CONTINUE.
      ENDTRY.

      IF ls_api_resp-all_records IS INITIAL.
        ls_result-outcome = 'ERROR'.
        ls_result-message = |Bank response ALL_RECORDS is empty (JL No:: { lv_je_list })|.
        write_log( iv_txn_id        = ls_head-transactionid
                   iv_idno          = ls_head-idno
                   iv_journal_alpha = lv_journal_alpha
                   lv_journal       = lv_journal
                   iv_companycode   = ls_head-companycode
                   iv_fiscalyear    = ls_head-fiscleyear
                   iv_utr           = ''
                   iv_status        = ''
                   iv_error         = ls_result-message
                   iv_body          = ls_api-body
                   iv_http_code     = ls_api-http_code ).
        APPEND ls_result TO rs_response-results.
        rs_response-error_count += 1.
        CONTINUE.
      ENDIF.

      DATA(ls_txn) = ls_api_resp-all_records[ 1 ].

      ls_result-payment_status = ls_txn-txn_status.

      IF ls_txn-txn_status <> 'Processed'.
        ls_result-outcome = 'INFO'.
        ls_result-message = |Payment is not processed till now from bank side.|
                         && | Bank TXN_STATUS: '{ ls_txn-txn_status }' (JL No:: { lv_je_list })|.
        write_log( iv_txn_id        = ls_head-transactionid
                   iv_idno          = ls_head-idno
                   iv_journal_alpha = lv_journal_alpha
                   lv_journal       = lv_journal
                   iv_companycode   = ls_head-companycode
                   iv_fiscalyear    = ls_head-fiscleyear
                   iv_utr           = ''
                   iv_status        = ls_txn-txn_status
                   iv_error         = ls_result-message
                   iv_body          = ls_api-body
                   iv_http_code     = ls_api-http_code ).
        APPEND ls_result TO rs_response-results.
        rs_response-skipped_count += 1.
        CONTINUE.
      ENDIF.


      DATA(lv_final_utr) = COND string(
        WHEN ls_txn-utr_no IS NOT INITIAL           THEN ls_txn-utr_no
        WHEN ls_txn-txn_reference_no IS NOT INITIAL THEN ls_txn-txn_reference_no
        ELSE '' ).

      ls_result-utr_number = lv_final_utr.

      IF lv_final_utr IS INITIAL.
        ls_result-outcome = 'ERROR'.
        ls_result-message = |TXN_STATUS Processed but both UTR_NO and TXN_REFERENCE_NO missing from bank response. (JL No:: { lv_je_list })|.
        write_log( iv_txn_id        = ls_head-transactionid
                   iv_idno          = ls_head-idno
                   iv_journal_alpha = lv_journal_alpha
                   lv_journal       = lv_journal
                   iv_companycode   = ls_head-companycode
                   iv_fiscalyear    = ls_head-fiscleyear
                   iv_utr           = ''
                   iv_status        = ls_txn-txn_status
                   iv_error         = ls_result-message
                   iv_body          = ls_api-body
                   iv_http_code     = ls_api-http_code ).
        APPEND ls_result TO rs_response-results.
        rs_response-error_count += 1.
        CONTINUE.
      ENDIF.

      "---- DB update: WHERE transactionid = ... -> saare invoices cover ----
      DATA(lv_db_err) = update_success(
                          iv_txn_id        = ls_head-transactionid
                          iv_idno         = ls_head-idno
                          iv_journal_alpha = lv_journal_alpha
                          lv_journal       = lv_journal
                          iv_companycode   = ls_head-companycode
                          iv_fiscalyear    = ls_head-fiscleyear
                          iv_utr           = lv_final_utr
                          iv_status        = ls_txn-txn_status ).

      IF lv_db_err IS INITIAL.
        DATA(lv_src) = COND string(
          WHEN ls_txn-utr_no IS NOT INITIAL THEN 'UTR_NO'
          ELSE 'TXN_REFERENCE_NO' ).
        ls_result-outcome = 'SUCCESS'.
        ls_result-message = |UTR { lv_final_utr } updated for { lines( lt_grp ) } invoice(s) (source: { lv_src }).|
                         && | Bank status: { ls_txn-txn_status }. JL No:: { lv_je_list }|.
        rs_response-success_count += 1.
      ELSE.
        ls_result-outcome = 'ERROR'.
        ls_result-message = |{ lv_db_err } (JL No:: { lv_je_list })|.
        rs_response-error_count += 1.
      ENDIF.

      APPEND ls_result TO rs_response-results.

    ENDLOOP.

  ENDMETHOD.


  METHOD build_payload.

    DATA loginid TYPE string.
    DATA INPUTgcip TYPE string.

    TRY.
        DATA(lv_sys_url_h) = cl_abap_context_info=>get_system_url( ).
      CATCH cx_abap_context_info_error.
        lv_sys_url_h = ''.
    ENDTRY.

    loginid = SWITCH string( lv_sys_url_h
      WHEN 'my434946.s4hana.cloud.sap' THEN 'APIUSER@CBXMGRT4'
      WHEN 'my436356.s4hana.cloud.sap' THEN 'APIUSER@CBXMGRT4'
      WHEN 'my438594.s4hana.cloud.sap' THEN 'APIUSER'
      ELSE 'APIUSER@CBXMGRT4' ).

    INPUTgcip = SWITCH string( lv_sys_url_h
      WHEN 'my434946.s4hana.cloud.sap' THEN 'CBXMGRT4'
      WHEN 'my436356.s4hana.cloud.sap' THEN 'CBXMGRT4'
      WHEN 'my438594.s4hana.cloud.sap' THEN 'PSYCHOTRCX'
      ELSE 'CBXMGRT4' ).

    DATA(lv_dt) = |{ iv_ref_no(4) }-{ iv_ref_no+4(2) }-{ iv_ref_no+6(2) }|.
    rv_json = |\{"INPUT_GCIF":"{ INPUTgcip }","LOGIN_ID":"{ loginid }",|
           && |"CBX_API_REF_NO":"{ iv_ref_no }","TXNDATE":"{ lv_dt }"\}|.
  ENDMETHOD.


  METHOD build_yesbank_payload.

    TRY.
        DATA(lv_sys_url_h) = cl_abap_context_info=>get_system_url( ).
      CATCH cx_abap_context_info_error.
        lv_sys_url_h = ''.
    ENDTRY.

    DATA(lv_consentid) = SWITCH string( lv_sys_url_h
      WHEN 'my434946.s4hana.cloud.sap' THEN '358600'   " TODO PRD consent
      WHEN 'my436356.s4hana.cloud.sap' THEN '358600'   " TODO QA  consent
      WHEN 'my438594.s4hana.cloud.sap' THEN '358600'   " TODO UAT consent
      ELSE '358600' ).                                  " TODO placeholder

    rv_json = |\{"Data":\{"InstrId":"{ iv_ref_no }",|
           && |"SecondaryIdentification":"{ lv_consentid }",|
           && |"ConsentId":"{ lv_consentid }"\}\}|.
  ENDMETHOD.


  METHOD call_cpi_api.
    TRY.

        DATA: lv_cpi_url  TYPE string,
              lv_username TYPE string,
              lv_password TYPE string.

        DATA(lv_url) = cl_abap_context_info=>get_system_url(  ).
        IF lv_url = 'my434946.s4hana.cloud.sap'.
          lv_cpi_url  = 'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/DEV/HDFC/Payment_Status'.
          lv_username = 'sb-e0695cf3-8f56-48f1-b1f8-49e7f90f4762!b40612|it-rt-pil-btp-prd-environment-bbojexhh!b148'.
          lv_password = 'b6a16460-0167-4c38-9338-66a82cd5e5ae$NqrKEUEBeHMklthaW_AWAoyJUyiiHzDWGyWgf6XtIk8='.

        ELSEIF lv_url = 'my436356.s4hana.cloud.sap'.

          lv_cpi_url  = 'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/DEV/HDFC/Payment_Status'.
          lv_username = 'sb-e0695cf3-8f56-48f1-b1f8-49e7f90f4762!b40612|it-rt-pil-btp-prd-environment-bbojexhh!b148'.
          lv_password = 'b6a16460-0167-4c38-9338-66a82cd5e5ae$NqrKEUEBeHMklthaW_AWAoyJUyiiHzDWGyWgf6XtIk8='.

        ELSEIF lv_url = 'my438594.s4hana.cloud.sap'.

          lv_cpi_url  = 'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/HDFC/Payment_Status'.
          lv_username = 'sb-e0695cf3-8f56-48f1-b1f8-49e7f90f4762!b40612|it-rt-pil-btp-prd-environment-bbojexhh!b148'.
          lv_password = 'b6a16460-0167-4c38-9338-66a82cd5e5ae$NqrKEUEBeHMklthaW_AWAoyJUyiiHzDWGyWgf6XtIk8='.
        ELSE.
          lv_cpi_url  = ''.
          lv_username = ''.
          lv_password = ''.

        ENDIF.

        DATA(lo_dest)   = cl_http_destination_provider=>create_by_url( lv_cpi_url ).
        DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination( lo_dest ).
        DATA(lo_req)    = lo_client->get_http_request( ).

        lo_req->set_authorization_basic( i_username = lv_username
                                         i_password = lv_password ).
        lo_req->set_header_field( i_name = 'Content-Type' i_value = 'application/json' ).
        lo_req->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).
        lo_req->set_text( i_text = iv_payload ).

        DATA(lo_resp)       = lo_client->execute( i_method = if_web_http_client=>post ).
        rs_result-http_code = lo_resp->get_status( )-code.
        rs_result-body      = lo_resp->get_text( ).
        rs_result-is_ok     = xsdbool( rs_result-http_code BETWEEN 200 AND 299 ).

        IF rs_result-is_ok = abap_false.
          rs_result-error_msg = |HTTP { rs_result-http_code }: { rs_result-body }|.
        ENDIF.

      CATCH cx_http_dest_provider_error INTO DATA(lx_dest).
        rs_result-is_ok     = abap_false.
        rs_result-http_code = 0.
        rs_result-error_msg = |Destination error: { lx_dest->get_text( ) }|.
        rs_result-body      = rs_result-error_msg.
      CATCH cx_web_http_client_error INTO DATA(lx_http).
        rs_result-is_ok     = abap_false.
        rs_result-http_code = 0.
        rs_result-error_msg = |HTTP client error: { lx_http->get_text( ) }|.
        rs_result-body      = rs_result-error_msg.
      CATCH cx_root INTO DATA(lx_root).
        rs_result-is_ok     = abap_false.
        rs_result-http_code = 0.
        rs_result-error_msg = |Unexpected error: { lx_root->get_text( ) }|.
        rs_result-body      = rs_result-error_msg.
    ENDTRY.
  ENDMETHOD.


 METHOD call_yesbank_api.
    TRY.

        DATA: lv_yb_url   TYPE string,
              lv_username TYPE string,
              lv_password TYPE string.

        DATA(lv_url) = cl_abap_context_info=>get_system_url(  ).
        IF lv_url = 'my434946.s4hana.cloud.sap'.
          lv_yb_url   = 'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/UAT/YesBank/Inquiry'. " TODO PRD url
          lv_username = 'sb-e0695cf3-8f56-48f1-b1f8-49e7f90f4762!b40612|it-rt-pil-btp-prd-environment-bbojexhh!b148'. " TODO YB user
          lv_password = 'b6a16460-0167-4c38-9338-66a82cd5e5ae$NqrKEUEBeHMklthaW_AWAoyJUyiiHzDWGyWgf6XtIk8='.         " TODO YB pass

        ELSEIF lv_url = 'my436356.s4hana.cloud.sap'.

          lv_yb_url   = 'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/UAT/YesBank/Inquiry'. " TODO QA url
          lv_username = 'sb-e0695cf3-8f56-48f1-b1f8-49e7f90f4762!b40612|it-rt-pil-btp-prd-environment-bbojexhh!b148'. " TODO YB user
          lv_password = 'b6a16460-0167-4c38-9338-66a82cd5e5ae$NqrKEUEBeHMklthaW_AWAoyJUyiiHzDWGyWgf6XtIk8='.         " TODO YB pass

        ELSEIF lv_url = 'my438594.s4hana.cloud.sap'.

          lv_yb_url   = 'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/UAT/YesBank/Inquiry'.
          lv_username = 'sb-e0695cf3-8f56-48f1-b1f8-49e7f90f4762!b40612|it-rt-pil-btp-prd-environment-bbojexhh!b148'. " TODO YB user
          lv_password = 'b6a16460-0167-4c38-9338-66a82cd5e5ae$NqrKEUEBeHMklthaW_AWAoyJUyiiHzDWGyWgf6XtIk8='.         " TODO YB pass
        ELSE.
          lv_yb_url   = ''.
          lv_username = ''.
          lv_password = ''.

        ENDIF.

        DATA(lo_dest)   = cl_http_destination_provider=>create_by_url( lv_yb_url ).
        DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination( lo_dest ).
        DATA(lo_req)    = lo_client->get_http_request( ).

        lo_req->set_authorization_basic( i_username = lv_username
                                         i_password = lv_password ).
        lo_req->set_header_field( i_name = 'Content-Type' i_value = 'application/json' ).
        lo_req->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).
        lo_req->set_text( i_text = iv_payload ).

        DATA(lo_resp)       = lo_client->execute( i_method = if_web_http_client=>post ).
        rs_result-http_code = lo_resp->get_status( )-code.
        rs_result-body      = lo_resp->get_text( ).
        rs_result-is_ok     = xsdbool( rs_result-http_code BETWEEN 200 AND 299 ).

        IF rs_result-is_ok = abap_false.
          rs_result-error_msg = |HTTP { rs_result-http_code }: { rs_result-body }|.
        ENDIF.

      CATCH cx_http_dest_provider_error INTO DATA(lx_dest).
        rs_result-is_ok     = abap_false.
        rs_result-http_code = 0.
        rs_result-error_msg = |Destination error: { lx_dest->get_text( ) }|.
        rs_result-body      = rs_result-error_msg.
      CATCH cx_web_http_client_error INTO DATA(lx_http).
        rs_result-is_ok     = abap_false.
        rs_result-http_code = 0.
        rs_result-error_msg = |HTTP client error: { lx_http->get_text( ) }|.
        rs_result-body      = rs_result-error_msg.
      CATCH cx_root INTO DATA(lx_root).
        rs_result-is_ok     = abap_false.
        rs_result-http_code = 0.
        rs_result-error_msg = |Unexpected error: { lx_root->get_text( ) }|.
        rs_result-body      = rs_result-error_msg.
    ENDTRY.
  ENDMETHOD.


  METHOD update_success.
    TRY.

        UPDATE zvendor_payment
          SET utrnumber      = @iv_utr,
              payment_status = @iv_status
          WHERE transactionid = @iv_txn_id.

        DATA(lv_vp_subrc) = sy-subrc.
        DATA(lv_vp_rows)  = sy-dbcnt.

        IF lv_vp_subrc <> 0 OR lv_vp_rows = 0.
          ROLLBACK WORK.
          rv_error = |ZVENDOR_PAYMENT update failed (subrc { lv_vp_subrc }, rows { lv_vp_rows }) for TxnID { iv_txn_id }.|.
          write_log( iv_txn_id        = iv_txn_id
                     iv_idno          = iv_idno
                     iv_journal_alpha = iv_journal_alpha
                     lv_journal  = lv_journal
                     iv_companycode   = iv_companycode
                     iv_fiscalyear    = iv_fiscalyear
                     iv_utr           = iv_utr
                     iv_status        = iv_status
                     iv_error         = rv_error
                     iv_body          = ''
                     iv_http_code     = 0 ).
          RETURN.
        ENDIF.

        " Us txnid ke saare log records update karo (multiple invoices)
        UPDATE zbank_pam_log
          SET utrnumber      = @iv_utr,
              payment_status = @iv_status,
              error          = @space
          WHERE transactionid = @iv_txn_id.

        IF sy-subrc <> 0 OR sy-dbcnt = 0.
          INSERT zbank_pam_log FROM @( VALUE #(
            client         = sy-mandt
            transactionid  = iv_txn_id
            id_no          = iv_idno
            journal_entry  = lv_journal
            companycode    = iv_companycode
            fiscalyear     = iv_fiscalyear
            utrnumber      = iv_utr
            payment_status = iv_status
            error          = '' ) ).
        ENDIF.

        COMMIT WORK AND WAIT.

        SELECT SINGLE utrnumber, payment_status
          FROM zvendor_payment
          WHERE transactionid = @iv_txn_id
          INTO @DATA(ls_verify).

        IF sy-subrc <> 0 OR ls_verify-utrnumber <> iv_utr.
          rv_error = |ZVENDOR_PAYMENT UTR update could not be verified after commit for TxnID { iv_txn_id }.|.
          write_log( iv_txn_id        = iv_txn_id
                     iv_idno          = iv_idno
                     iv_journal_alpha = iv_journal_alpha
                     lv_journal       = lv_journal
                     iv_companycode   = iv_companycode
                     iv_fiscalyear    = iv_fiscalyear
                     iv_utr           = iv_utr
                     iv_status        = iv_status
                     iv_error         = rv_error
                     iv_body          = ''
                     iv_http_code     = 0 ).
          RETURN.
        ENDIF.

      CATCH cx_root INTO DATA(lx).
        ROLLBACK WORK.
        rv_error = |DB update/commit failed: { lx->get_text( ) }|.
        write_log( iv_txn_id        = iv_txn_id
                   iv_idno          = iv_idno
                   iv_journal_alpha = iv_journal_alpha
                   lv_journal       = lv_journal
                   iv_companycode   = iv_companycode
                   iv_fiscalyear    = iv_fiscalyear
                   iv_utr           = iv_utr
                   iv_status        = iv_status
                   iv_error         = rv_error
                   iv_body          = ''
                   iv_http_code     = 0 ).
    ENDTRY.
  ENDMETHOD.


  METHOD write_log.
    TRY.
        DATA(lv_body) = COND string(
          WHEN strlen( iv_body ) > c_body_max_len THEN iv_body(c_body_max_len)
          ELSE iv_body ).

        UPDATE zbank_pam_log
          SET utrnumber      = @iv_utr,
              payment_status = @iv_status,
              error          = @iv_error
          WHERE transactionid = @iv_txn_id
            AND id_no         = @iv_idno
            AND journal_entry = @lv_journal
            AND companycode   = @iv_companycode
            AND fiscalyear    = @iv_fiscalyear.

        IF sy-subrc <> 0 OR sy-dbcnt = 0.
          INSERT zbank_pam_log FROM @( VALUE #(
            client         = sy-mandt
            transactionid  = iv_txn_id
            id_no          = iv_idno
            journal_entry  = lv_journal
            companycode    = iv_companycode
            fiscalyear     = iv_fiscalyear
            utrnumber      = iv_utr
            payment_status = iv_status
            error          = iv_error ) ).
        ENDIF.

        COMMIT WORK AND WAIT.
      CATCH cx_root.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
