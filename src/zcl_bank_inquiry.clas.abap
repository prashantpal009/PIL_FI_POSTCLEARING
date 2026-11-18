CLASS zcl_bank_inquiry DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_apj_dt_exec_object.
    INTERFACES if_apj_rt_exec_object.

  PRIVATE SECTION.

    CONSTANTS c_id_txnid         TYPE string VALUE 'P_TXNID'.
    CONSTANTS c_id_date          TYPE string VALUE 'P_DATE'.
    CONSTANTS c_gcif             TYPE string VALUE 'CBXMGRT3'.
    CONSTANTS c_login_id         TYPE string VALUE 'APIUSER@CBXMGRT3'.
    CONSTANTS c_filter_val       TYPE string VALUE ''.
    CONSTANTS c_status_accepted  TYPE string VALUE 'Accepted'.
    CONSTANTS c_status_completed TYPE string VALUE 'Completed'.
    CONSTANTS c_content_type     TYPE string VALUE 'application/json'.
    CONSTANTS c_body_max_len     TYPE i      VALUE 1000.

    TYPES: BEGIN OF ty_txn_record,
             utr_no     TYPE string,
             txn_status TYPE string,
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

    METHODS get_inquiry
      IMPORTING iv_txnid TYPE c
                iv_date  TYPE d.

    METHODS call_cpi_api
      IMPORTING iv_payload       TYPE string
      RETURNING VALUE(rs_result) TYPE ty_api_result.

    METHODS build_payload
      IMPORTING iv_ref_no      TYPE clike
                iv_date        TYPE d
      RETURNING VALUE(rv_json) TYPE string.

    METHODS update_success
      IMPORTING iv_txn_id  TYPE clike
                iv_journal TYPE belnr_d
                iv_utr     TYPE string.

    METHODS write_log
      IMPORTING iv_txn_id    TYPE clike
                iv_journal   TYPE belnr_d
                iv_utr       TYPE string
                iv_status    TYPE string
                iv_error     TYPE string
                iv_body      TYPE string
                iv_http_code TYPE i.

ENDCLASS.



CLASS ZCL_BANK_INQUIRY IMPLEMENTATION.


  METHOD if_apj_rt_exec_object~execute.

    DATA lv_txnid TYPE c LENGTH 20.
    DATA lv_date  TYPE d.

    READ TABLE it_parameters ASSIGNING FIELD-SYMBOL(<t>) WITH KEY selname = c_id_txnid.
    IF sy-subrc = 0. lv_txnid = <t>-low. ENDIF.

    READ TABLE it_parameters ASSIGNING FIELD-SYMBOL(<d>) WITH KEY selname = c_id_date.
    IF sy-subrc = 0 AND <d>-low IS NOT INITIAL.
      lv_date = <d>-low.
    ELSE.
      lv_date = sy-datum.
    ENDIF.

    get_inquiry( iv_txnid = lv_txnid
                 iv_date  = lv_date ).

  ENDMETHOD.


  METHOD call_cpi_api.
    TRY.
        "-- Resolve CPI URL and credentials based on current system URL
        DATA(lv_sys_url) = cl_abap_context_info=>get_system_url( ).

        DATA(lv_cpi_url) = SWITCH string( lv_sys_url
   WHEN 'my434946.s4hana.cloud.sap' THEN
     'https://pil-btp-dev-environment-komwgeht.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/HDFC/Inquiry'
   WHEN 'my436356.s4hana.cloud.sap' THEN
     'https://pil-btp-dev-environment-komwgeht.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/HDFC/Inquiry'
   WHEN 'my438594.s4hana.cloud.sap' THEN
     'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/HDFC/Inquiry'
   ELSE
     THROW cx_web_message_error( ) ).

        DATA(lv_username) = SWITCH string( lv_sys_url
   WHEN 'my434946.s4hana.cloud.sap' THEN
     'sb-253515aa-a466-4244-98b4-efd5f08b4596!b40610|it-rt-pil-btp-dev-environment-komwgeht!b148'
   WHEN 'my436356.s4hana.cloud.sap' THEN
     'sb-253515aa-a466-4244-98b4-efd5f08b4596!b40610|it-rt-pil-btp-dev-environment-komwgeht!b148'
   WHEN 'my438594.s4hana.cloud.sap' THEN
     'sb-e0695cf3-8f56-48f1-b1f8-49e7f90f4762!b40612|it-rt-pil-btp-prd-environment-bbojexhh!b148'
   ELSE `` ).

        DATA(lv_password) = SWITCH string( lv_sys_url
     WHEN 'my434946.s4hana.cloud.sap' THEN
       'a2ad445c-139f-4fba-bbb2-8b52fd43b462$muTSUO92h0uOT-3LtS9aWFSDdbru8HxS1XKKRpkooVI='
     WHEN 'my436356.s4hana.cloud.sap' THEN
       'a2ad445c-139f-4fba-bbb2-8b52fd43b462$muTSUO92h0uOT-3LtS9aWFSDdbru8HxS1XKKRpkooVI='
     WHEN 'my438594.s4hana.cloud.sap' THEN
       'b6a16460-0167-4c38-9338-66a82cd5e5ae$NqrKEUEBeHMklthaW_AWAoyJUyiiHzDWGyWgf6XtIk8='
     ELSE `` ).

        IF lv_cpi_url IS INITIAL.
          rs_result-is_ok     = abap_false.
          rs_result-http_code = 0.
          rs_result-error_msg = |No CPI URL configured for system: { lv_sys_url }|.
          rs_result-body      = rs_result-error_msg.
          RETURN.
        ENDIF.

        DATA(lo_dest)   = cl_http_destination_provider=>create_by_url( lv_cpi_url ).
        DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination( lo_dest ).
        DATA(lo_req)    = lo_client->get_http_request( ).

        lo_req->set_authorization_basic( i_username = lv_username
                                          i_password = lv_password ).
        lo_req->set_header_field( i_name = 'Content-Type' i_value = c_content_type ).
        lo_req->set_header_field( i_name = 'Accept'       i_value = c_content_type ).
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


  METHOD write_log.
    TRY.
        DATA(lv_body) = COND string(
          WHEN strlen( iv_body ) > c_body_max_len THEN iv_body(c_body_max_len)
          ELSE iv_body ).

        MODIFY zbank_pam_log FROM @( VALUE #(
          transactionid  = iv_txn_id
          journal_entry  = iv_journal
          utrnumber      = iv_utr
          payment_status = iv_status
          error          = iv_error ) ).

        COMMIT WORK AND WAIT.
      CATCH cx_root.
    ENDTRY.
  ENDMETHOD.


  METHOD update_success.
    TRY.

        UPDATE zvendor_payment
          SET utrnumber      = @iv_utr,
              payment_status = @c_status_completed
          WHERE transactionid = @iv_txn_id.

        IF sy-subrc <> 0.
          write_log( iv_txn_id    = iv_txn_id
                     iv_journal   = iv_journal
                     iv_utr       = iv_utr
                     iv_status    = c_status_completed
                     iv_error     = 'UPDATE on zvendor_payment returned SY-SUBRC <> 0'
                     iv_body      = ''
                     iv_http_code = 0 ).
          RETURN.
        ENDIF.

        MODIFY zbank_pam_log FROM @( VALUE #(
          transactionid  = iv_txn_id
          journal_entry  = iv_journal
          utrnumber      = iv_utr
          payment_status = c_status_completed
          error          = ''  ) ).

        COMMIT WORK AND WAIT.

      CATCH cx_root INTO DATA(lx).
        ROLLBACK WORK.
        write_log( iv_txn_id    = iv_txn_id
                   iv_journal   = iv_journal
                   iv_utr       = iv_utr
                   iv_status    = ''
                   iv_error     = |DB commit failed: { lx->get_text( ) }|
                   iv_body      = ''
                   iv_http_code = 0 ).
    ENDTRY.
  ENDMETHOD.


  METHOD get_inquiry.

    IF iv_txnid IS NOT INITIAL.
      SELECT transactionid, payment_status, utrnumber, id_no, journal_entry
        FROM zvendor_payment
        WHERE transactionid = @iv_txnid
          AND payment_status = @c_status_accepted
          AND utrnumber IS INITIAL
        INTO TABLE @DATA(lt_payments).
    ELSE.
      SELECT transactionid, payment_status, utrnumber, id_no, journal_entry
        FROM zvendor_payment
        WHERE transactionid IS NOT INITIAL
          AND payment_status = @c_status_accepted
          AND utrnumber IS INITIAL
        INTO TABLE @lt_payments.
    ENDIF.

    CHECK lt_payments IS NOT INITIAL.

    LOOP AT lt_payments ASSIGNING FIELD-SYMBOL(<pay>).

      DATA(ls_result) = call_cpi_api(
                          build_payload( iv_ref_no = <pay>-transactionid
                                         iv_date   = iv_date ) ).

      IF ls_result-is_ok = abap_false.
        write_log( iv_txn_id    = <pay>-transactionid
                   iv_journal   = <pay>-journal_entry
                   iv_utr       = ''
                   iv_status    = ''
                   iv_error     = ls_result-error_msg
                   iv_body      = ls_result-body
                   iv_http_code = ls_result-http_code ).
        CONTINUE.
      ENDIF.

      DATA ls_api_resp TYPE ty_api_response.
      TRY.
          /ui2/cl_json=>deserialize(
            EXPORTING json        = ls_result-body
                      pretty_name = /ui2/cl_json=>pretty_mode-low_case
            CHANGING  data        = ls_api_resp ).
        CATCH cx_root INTO DATA(lx_json).
          write_log( iv_txn_id    = <pay>-transactionid
                     iv_journal   = <pay>-journal_entry
                     iv_utr       = ''
                     iv_status    = ''
                     iv_error     = |JSON parse failed: { lx_json->get_text( ) }|
                     iv_body      = ls_result-body
                     iv_http_code = ls_result-http_code ).
          CONTINUE.
      ENDTRY.

      IF ls_api_resp-all_records IS INITIAL.
        write_log( iv_txn_id    = <pay>-transactionid
                   iv_journal   = <pay>-journal_entry
                   iv_utr       = ''
                   iv_status    = ''
                   iv_error     = 'Response ALL_RECORDS is empty'
                   iv_body      = ls_result-body
                   iv_http_code = ls_result-http_code ).
        CONTINUE.
      ENDIF.

      DATA(ls_txn) = ls_api_resp-all_records[ 1 ].

      IF ls_txn-utr_no IS INITIAL.
        write_log( iv_txn_id    = <pay>-transactionid
                   iv_journal   = <pay>-journal_entry
                   iv_utr       = ''
                   iv_status    = ls_txn-txn_status
                   iv_error     = |UTR missing in response. Bank status: '{ ls_txn-txn_status }'|
                   iv_body      = ls_result-body
                   iv_http_code = ls_result-http_code ).
        CONTINUE.
      ENDIF.

      IF ls_txn-txn_status <> c_status_completed.
        write_log( iv_txn_id    = <pay>-transactionid
                   iv_journal   = <pay>-journal_entry
                   iv_utr       = ls_txn-utr_no
                   iv_status    = ls_txn-txn_status
                   iv_error     = |Status '{ ls_txn-txn_status }' is not Completed – update skipped|
                   iv_body      = ls_result-body
                   iv_http_code = ls_result-http_code ).
        CONTINUE.
      ENDIF.

      update_success( iv_txn_id  = <pay>-transactionid
                      iv_journal = <pay>-journal_entry
                      iv_utr     = ls_txn-utr_no ).

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

    DATA(lv_dt) = |{ iv_date(4) }-{ iv_date+4(2) }-{ iv_date+6(2) }|.
    rv_json = |\{"INPUT_GCIF":"{ INPUTgcip }","LOGIN_ID":"{ loginid }",|
           && |"FILTER1_VALUE_TXT":"{ c_filter_val }",|
           && |"CBX_API_REF_NO":"{ iv_ref_no }","TXNDATE":"{ lv_dt }"\}|.
  ENDMETHOD.


  METHOD if_apj_dt_exec_object~get_parameters.
    et_parameter_def = VALUE #(
      ( selname = c_id_txnid kind = if_apj_dt_exec_object=>parameter
        datatype = 'C' length = 20 param_text = 'Transaction ID (optional)' )
      ( selname = c_id_date  kind = if_apj_dt_exec_object=>parameter
        datatype = 'D'         param_text = 'Payment Date  (optional)'  )
    ).
  ENDMETHOD.
ENDCLASS.
