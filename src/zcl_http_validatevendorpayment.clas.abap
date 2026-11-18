CLASS zcl_http_validatevendorpayment DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_service_extension.

  PRIVATE SECTION.

    CONSTANTS c_body_max_len TYPE i VALUE 2000.

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

    TYPES: BEGIN OF ty_api_result,
             body      TYPE string,
             http_code TYPE i,
             is_ok     TYPE abap_bool,
             error_msg TYPE string,
           END OF ty_api_result.

    TYPES: BEGIN OF ty_txn_result,
             transaction_id TYPE string,
             id_no          TYPE string,
             journal_entry  TYPE string,
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

    METHODS process_validation
      IMPORTING it_items           TYPE ty_items
                iv_date            TYPE d
      RETURNING VALUE(rs_response) TYPE ty_final_response.

    METHODS call_cpi_api
      IMPORTING iv_payload       TYPE string
      RETURNING VALUE(rs_result) TYPE ty_api_result.

    METHODS build_payload
      IMPORTING iv_ref_no      TYPE clike
                iv_date        TYPE d
      RETURNING VALUE(rv_json) TYPE string.

    METHODS extract_bank_error
      IMPORTING iv_body          TYPE string
      RETURNING VALUE(rv_reason) TYPE string.

    METHODS clear_on_error
      IMPORTING iv_txn_id       TYPE clike
      RETURNING VALUE(rv_error) TYPE string.

    METHODS write_log
      IMPORTING iv_txn_id      TYPE clike
                iv_idno        TYPE clike OPTIONAL
                lv_journal     TYPE clike
                iv_companycode TYPE clike OPTIONAL
                iv_fiscalyear  TYPE clike OPTIONAL
                iv_status      TYPE string
                iv_error       TYPE string
                iv_body        TYPE string
                iv_http_code   TYPE i.

ENDCLASS.



CLASS ZCL_HTTP_VALIDATEVENDORPAYMENT IMPLEMENTATION.


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

    DATA(ls_response) = process_validation(
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


  METHOD process_validation.

    DATA ls_result   TYPE ty_txn_result.
    DATA ls_api_resp TYPE ty_api_response.

    rs_response-run_date = |{ iv_date(4) }-{ iv_date+4(2) }-{ iv_date+6(2) }|.
    rs_response-total    = lines( it_items ).

    LOOP AT it_items ASSIGNING FIELD-SYMBOL(<item>).

      CLEAR ls_result.
      CLEAR ls_api_resp.

      ls_result-transaction_id = <item>-transactionid.
      ls_result-id_no          = <item>-idno.
      ls_result-journal_entry  = <item>-journalentry.

      DATA(lv_journal) = CONV belnr_d( <item>-journalentry ).

        IF <item>-companycode = '2000'.
        ls_result-outcome = 'SKIPPED'.
        ls_result-message = |Validation not applicable for Company Code 2000 (Yes Bank).|.
        APPEND ls_result TO rs_response-results.
        rs_response-skipped_count += 1.
        CONTINUE.
      ENDIF.

      IF <item>-transactionid IS INITIAL.
        ls_result-outcome = 'ERROR'.
        ls_result-message = |TransactionId is empty for ID No: { <item>-idno }|.
        APPEND ls_result TO rs_response-results.
        rs_response-error_count += 1.
        CONTINUE.
      ENDIF.

*      IF <item>-transactionid IS INITIAL.
*        ls_result-outcome = 'ERROR'.
*        ls_result-message = |TransactionId is empty for ID No: { <item>-idno }|.
*        APPEND ls_result TO rs_response-results.
*        rs_response-error_count += 1.
*        CONTINUE.
*      ENDIF.

      DATA(ls_api) = call_cpi_api(
                       build_payload( iv_ref_no = <item>-transactionid
                                      iv_date   = iv_date ) ).

      ls_result-http_code = ls_api-http_code.

      IF ls_api-is_ok = abap_false.
        DATA(lv_clean_err) = extract_bank_error( ls_api-body ).
        IF lv_clean_err IS INITIAL.
          lv_clean_err = ls_api-error_msg.
        ENDIF.

        clear_on_error( <item>-transactionid ).
        ls_result-outcome = 'ERROR'.
        ls_result-message = lv_clean_err.
        write_log( iv_txn_id      = <item>-transactionid
                   iv_idno        = <item>-idno
                   lv_journal     = lv_journal
                   iv_companycode = <item>-companycode
                   iv_fiscalyear  = <item>-fiscleyear
                   iv_status      = ''
                   iv_error       = lv_clean_err
                   iv_body        = ls_api-body
                   iv_http_code   = ls_api-http_code ).
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
          clear_on_error( <item>-transactionid ).
          ls_result-outcome = 'ERROR'.
          ls_result-message = |JSON parse failed: { lx_json->get_text( ) }|.
          write_log( iv_txn_id      = <item>-transactionid
                     iv_idno        = <item>-idno
                     lv_journal     = lv_journal
                     iv_companycode = <item>-companycode
                     iv_fiscalyear  = <item>-fiscleyear
                     iv_status      = ''
                     iv_error       = ls_result-message
                     iv_body        = ls_api-body
                     iv_http_code   = ls_api-http_code ).
          APPEND ls_result TO rs_response-results.
          rs_response-error_count += 1.
          CONTINUE.
      ENDTRY.

      IF ls_api_resp-all_records IS INITIAL.
        clear_on_error( <item>-transactionid ).
        ls_result-outcome = 'ERROR'.
        ls_result-message = 'Transaction Not Found'.
        write_log( iv_txn_id      = <item>-transactionid
                   iv_idno        = <item>-idno
                   lv_journal     = lv_journal
                   iv_companycode = <item>-companycode
                   iv_fiscalyear  = <item>-fiscleyear
                   iv_status      = ''
                   iv_error       = ls_result-message
                   iv_body        = ls_api-body
                   iv_http_code   = ls_api-http_code ).
        APPEND ls_result TO rs_response-results.
        rs_response-error_count += 1.
        CONTINUE.
      ENDIF.

      DATA(ls_txn) = ls_api_resp-all_records[ 1 ].

      DATA(lv_status_u) = to_upper( ls_txn-status ).
      DATA(lv_desc_u)   = to_upper( ls_txn-od_status_desc ).

      IF lv_status_u CS 'ERROR'
         OR lv_status_u CS 'REJECT'
         OR lv_status_u CS 'FAIL'
         OR lv_desc_u   CS 'REJECT'
         OR lv_desc_u   CS 'FAIL'
         OR lv_desc_u   CS 'ERROR'.

        DATA(lv_bank_err) = COND string(
          WHEN ls_txn-od_status_desc   IS NOT INITIAL THEN ls_txn-od_status_desc
          WHEN ls_txn-od_reject_reason IS NOT INITIAL THEN |Rejected ({ ls_txn-od_reject_reason })|
          ELSE 'Transaction validation failed' ).

        clear_on_error( <item>-transactionid ).
        ls_result-outcome = 'ERROR'.
        ls_result-message = lv_bank_err.
        write_log( iv_txn_id      = <item>-transactionid
                   iv_idno        = <item>-idno
                   lv_journal     = lv_journal
                   iv_companycode = <item>-companycode
                   iv_fiscalyear  = <item>-fiscleyear
                   iv_status      = ls_txn-txn_status
                   iv_error       = lv_bank_err
                   iv_body        = ls_api-body
                   iv_http_code   = ls_api-http_code ).
        APPEND ls_result TO rs_response-results.
        rs_response-error_count += 1.
        CONTINUE.
      ENDIF.

      ls_result-outcome = 'SUCCESS'.
      ls_result-message = 'Payment Validated Successfully'.

      write_log( iv_txn_id      = <item>-transactionid
                 iv_idno        = <item>-idno
                 lv_journal     = lv_journal
                 iv_companycode = <item>-companycode
                 iv_fiscalyear  = <item>-fiscleyear
                 iv_status      = ls_txn-txn_status
                 iv_error       = ''
                 iv_body        = ls_api-body
                 iv_http_code   = ls_api-http_code ).

      APPEND ls_result TO rs_response-results.
      rs_response-success_count += 1.

    ENDLOOP.

  ENDMETHOD.


  METHOD build_payload.

    DATA loginid   TYPE string.
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


  METHOD call_cpi_api.
    TRY.

        DATA: lv_cpi_url  TYPE string,
              lv_username TYPE string,
              lv_password TYPE string.

        DATA(lv_url) = cl_abap_context_info=>get_system_url( ).
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


  METHOD extract_bank_error.
    TYPES: BEGIN OF ty_err,
             code   TYPE string,
             reason TYPE string,
           END OF ty_err.
    TYPES: BEGIN OF ty_err_resp,
             title  TYPE string,
             errors TYPE STANDARD TABLE OF ty_err WITH DEFAULT KEY,
           END OF ty_err_resp.

    DATA ls_err TYPE ty_err_resp.

    rv_reason = ''.

    TRY.
        /ui2/cl_json=>deserialize(
          EXPORTING json        = iv_body
                    pretty_name = /ui2/cl_json=>pretty_mode-low_case
          CHANGING  data        = ls_err ).
      CATCH cx_root.
        rv_reason = ''.
    ENDTRY.

    IF ls_err-errors IS NOT INITIAL.
      DATA(ls_first) = ls_err-errors[ 1 ].
      rv_reason = COND string(
        WHEN ls_first-reason IS NOT INITIAL AND ls_first-code IS NOT INITIAL
          THEN |{ ls_first-reason } (Code: { ls_first-code })|
        WHEN ls_first-reason IS NOT INITIAL
          THEN ls_first-reason
        ELSE ls_first-code ).
    ELSEIF ls_err-title IS NOT INITIAL.
      rv_reason = ls_err-title.
    ENDIF.
  ENDMETHOD.


  METHOD clear_on_error.
    TRY.
        IF iv_txn_id IS INITIAL.
          RETURN.
        ENDIF.

        UPDATE zvendor_payment
          SET transactionid  = @space,
              payment_status = @space
          WHERE transactionid = @iv_txn_id.

        IF sy-subrc <> 0 OR sy-dbcnt = 0.
          ROLLBACK WORK.
          rv_error = |ZVENDOR_PAYMENT clear failed for TxnID { iv_txn_id }.|.
          RETURN.
        ENDIF.

        COMMIT WORK AND WAIT.

      CATCH cx_root INTO DATA(lx).
        ROLLBACK WORK.
        rv_error = |Clear update failed: { lx->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.


  METHOD write_log.
    TRY.
        DATA(lv_body) = COND string(
          WHEN strlen( iv_body ) > c_body_max_len THEN iv_body(c_body_max_len)
          ELSE iv_body ).

        UPDATE zbank_pam_log
          SET payment_status = @iv_status,
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
            payment_status = iv_status
            error          = iv_error ) ).
        ENDIF.

        COMMIT WORK AND WAIT.
      CATCH cx_root.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
