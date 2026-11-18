    CLASS lhc_ZCDS_Vendor_PaymentRAP DEFINITION INHERITING FROM cl_abap_behavior_handler.
      PRIVATE SECTION.

        METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
          IMPORTING keys REQUEST requested_authorizations FOR ZCDS_Vendor_PaymentRAP RESULT result.

        METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
          IMPORTING REQUEST requested_authorizations FOR ZCDS_Vendor_PaymentRAP RESULT result.
        METHODS setDefaultValues FOR DETERMINE ON MODIFY
          IMPORTING keys FOR ZCDS_Vendor_PaymentRAP~setDefaultValues.
        METHODS get_instance_features FOR INSTANCE FEATURES
          IMPORTING keys REQUEST requested_features FOR ZCDS_Vendor_PaymentRAP RESULT result.

        METHODS approveProposal FOR MODIFY
          IMPORTING keys FOR ACTION ZCDS_Vendor_PaymentRAP~approveProposal RESULT result.

        METHODS rejectProposal FOR MODIFY
          IMPORTING keys FOR ACTION ZCDS_Vendor_PaymentRAP~rejectProposal RESULT result.
        METHODS reject2Proposal FOR MODIFY
          IMPORTING keys FOR ACTION ZCDS_Vendor_PaymentRAP~reject2Proposal RESULT result.
        METHODS approve2Proposal FOR MODIFY
          IMPORTING keys FOR ACTION ZCDS_Vendor_PaymentRAP~approve2Proposal RESULT result.
*        METHODS InvoicePosting FOR MODIFY
*          IMPORTING keys FOR ACTION ZCDS_Vendor_PaymentRAP~InvoicePosting RESULT result.

    ENDCLASS.

    CLASS lhc_ZCDS_Vendor_PaymentRAP IMPLEMENTATION.

      METHOD get_instance_authorizations.
      ENDMETHOD.

      METHOD get_global_authorizations.
      ENDMETHOD.

      METHOD setDefaultValues.

        DATA(lv_today) = cl_abap_context_info=>get_system_date( ).
        DATA(lv_cal_year)  = CONV i( lv_today+0(4) ).
        DATA(lv_cal_month) = CONV i( lv_today+4(2) ).

        DATA(lv_fiscal_year) = COND i(
                                 WHEN lv_cal_month <= 3
                                 THEN lv_cal_year - 1
                                 ELSE lv_cal_year ).

        DATA(lv_fy_prefix) = |{ lv_fiscal_year ALIGN = RIGHT WIDTH = 4 PAD = '0' }|.

        READ ENTITIES OF ZCDS_Vendor_PaymentRAP IN LOCAL MODE
          ENTITY ZCDS_Vendor_PaymentRAP
          FIELDS ( CompanyCode IdNo )
          WITH CORRESPONDING #( keys )
          RESULT DATA(lt_proposals).

*        LOOP AT lt_proposals ASSIGNING FIELD-SYMBOL(<ls_proposal>).
*
*          IF <ls_proposal>-IdNo IS NOT INITIAL.
*            CONTINUE.
*          ENDIF.
*
*          DATA(lv_search_pattern) = |{ lv_fy_prefix }%|.
*
*          SELECT SINGLE MAX( id_no )
*            FROM zvendor_payment
*            WHERE company_code = @<ls_proposal>-CompanyCode
*              AND id_no        LIKE @lv_search_pattern
*            INTO @DATA(lv_max_id).
*
*          DATA(lv_new_id) = COND #(
*                              WHEN lv_max_id IS INITIAL
*                              THEN |{ lv_fy_prefix }000001|
*                              ELSE |{ lv_fy_prefix }{ CONV i( lv_max_id+4(6) ) + 1 ALIGN = RIGHT WIDTH = 6 PAD = '0' }| ).
*
*          MODIFY ENTITIES OF ZCDS_Vendor_PaymentRAP IN LOCAL MODE
*            ENTITY ZCDS_Vendor_PaymentRAP
*            UPDATE FIELDS ( IdNo )
*            WITH VALUE #( ( %tky = <ls_proposal>-%tky IdNo = lv_new_id ) ).
*
*        ENDLOOP.
*
*      ENDMETHOD.
LOOP AT lt_proposals ASSIGNING FIELD-SYMBOL(<ls_proposal>).

      IF <ls_proposal>-IdNo IS NOT INITIAL.
        CONTINUE.
      ENDIF.
      DATA(lv_start_seq) = COND i(
                             WHEN <ls_proposal>-CompanyCode = '1000' THEN 1
                             WHEN <ls_proposal>-CompanyCode = '2000' THEN 100001
                             ELSE 1 ).

      DATA(lv_search_pattern) = |{ lv_fy_prefix }%|.

      SELECT SINGLE MAX( id_no )
        FROM zvendor_payment
        WHERE company_code = @<ls_proposal>-CompanyCode
          AND id_no        LIKE @lv_search_pattern
        INTO @DATA(lv_max_id).

      DATA(lv_new_id) = COND #(
                          WHEN lv_max_id IS INITIAL
                          THEN |{ lv_fy_prefix }{ lv_start_seq ALIGN = RIGHT WIDTH = 6 PAD = '0' }|
                          ELSE |{ lv_fy_prefix }{ CONV i( lv_max_id+4(6) ) + 1 ALIGN = RIGHT WIDTH = 6 PAD = '0' }| ).

      MODIFY ENTITIES OF ZCDS_Vendor_PaymentRAP IN LOCAL MODE
        ENTITY ZCDS_Vendor_PaymentRAP
        UPDATE FIELDS ( IdNo )
        WITH VALUE #( ( %tky = <ls_proposal>-%tky IdNo = lv_new_id ) ).

    ENDLOOP.

  ENDMETHOD.

      METHOD get_instance_features.
      ENDMETHOD.

      METHOD approveProposal.
        DATA: lt_update TYPE TABLE FOR UPDATE ZCDS_Vendor_PaymentRAP.
        DATA: lv_system_date TYPE d,
              lv_system_time TYPE t,
              lv_timezone    TYPE timezone.

        TRY.

            lv_timezone = cl_abap_context_info=>get_user_time_zone( ).

            CONVERT UTCLONG utclong_current( )
                    TIME ZONE lv_timezone
                    INTO DATE lv_system_date
                         TIME lv_system_time.

          CATCH cx_abap_context_info_error INTO DATA(lx_error).

            lv_timezone = 'UTC'.

        ENDTRY.

*        lv_timezone = cl_abap_context_info=>get_user_time_zone( ).

        CONVERT UTCLONG utclong_current( )
                TIME ZONE lv_timezone
                INTO DATE lv_system_date
                     TIME lv_system_time.

        LOOP AT keys ASSIGNING FIELD-SYMBOL(<ls_key>).
          APPEND VALUE #(
                    Db_Key           = <ls_key>-Db_Key
                    Approval1Status  = abap_true
                    Approval1User    = sy-uname
                    Approval1On      = lv_system_date
                    Approval1Time    = lv_system_time
                    %control-Approval1Status = if_abap_behv=>mk-on
                    %control-Approval1User   = if_abap_behv=>mk-on
                    %control-Approval1On     = if_abap_behv=>mk-on
                    %control-Approval1Time   = if_abap_behv=>mk-on
                  ) TO lt_update.
        ENDLOOP.

        MODIFY ENTITIES OF ZCDS_Vendor_PaymentRAP IN LOCAL MODE
          ENTITY ZCDS_Vendor_PaymentRAP
          UPDATE FIELDS ( Approval1Status Approval1User Approval1On Approval1Time )
          WITH lt_update
          REPORTED DATA(lt_reported)
          FAILED DATA(lt_failed).

        IF lt_failed IS NOT INITIAL.
          failed-zcds_vendor_paymentrap   = CORRESPONDING #( lt_failed-zcds_vendor_paymentrap ).
          reported-zcds_vendor_paymentrap = CORRESPONDING #( lt_reported-zcds_vendor_paymentrap ).
        ELSE.
          reported-zcds_vendor_paymentrap = VALUE #( (
              Db_Key = keys[ 1 ]-Db_Key
              %msg   = new_message_with_text(
                           severity = if_abap_behv_message=>severity-success
                           text     = 'Proposal approved successfully' )
          ) ).
        ENDIF.
      ENDMETHOD.

      METHOD rejectProposal.

        DATA: lt_delete TYPE TABLE FOR DELETE ZCDS_Vendor_PaymentRAP.

        LOOP AT keys ASSIGNING FIELD-SYMBOL(<ls_key>).
          APPEND VALUE #(
                    Db_Key = <ls_key>-Db_Key
                  ) TO lt_delete.
        ENDLOOP.

        MODIFY ENTITIES OF ZCDS_Vendor_PaymentRAP IN LOCAL MODE
          ENTITY ZCDS_Vendor_PaymentRAP
          DELETE
          FROM lt_delete
          REPORTED DATA(lt_reported)
          FAILED   DATA(lt_failed).

        IF lt_failed IS NOT INITIAL.
          failed-zcds_vendor_paymentrap   = CORRESPONDING #( lt_failed-zcds_vendor_paymentrap ).
          reported-zcds_vendor_paymentrap = CORRESPONDING #( lt_reported-zcds_vendor_paymentrap ).
        ELSE.
          reported-zcds_vendor_paymentrap = VALUE #( (
              Db_Key = keys[ 1 ]-Db_Key
              %msg   = new_message_with_text(
                           severity = if_abap_behv_message=>severity-success
                           text     = 'Proposal rejected and deleted successfully' )
          ) ).
        ENDIF.

      ENDMETHOD.

      METHOD reject2Proposal.

        DATA: lt_delete TYPE TABLE FOR DELETE ZCDS_Vendor_PaymentRAP.

        LOOP AT keys ASSIGNING FIELD-SYMBOL(<ls_key>).
          APPEND VALUE #(
                    Db_Key = <ls_key>-Db_Key
                  ) TO lt_delete.
        ENDLOOP.

        MODIFY ENTITIES OF ZCDS_Vendor_PaymentRAP IN LOCAL MODE
          ENTITY ZCDS_Vendor_PaymentRAP
          DELETE
          FROM lt_delete
          REPORTED DATA(lt_reported)
          FAILED   DATA(lt_failed).

        IF lt_failed IS NOT INITIAL.
          failed-zcds_vendor_paymentrap   = CORRESPONDING #( lt_failed-zcds_vendor_paymentrap ).
          reported-zcds_vendor_paymentrap = CORRESPONDING #( lt_reported-zcds_vendor_paymentrap ).
        ELSE.
          reported-zcds_vendor_paymentrap = VALUE #( (
              Db_Key = keys[ 1 ]-Db_Key
              %msg   = new_message_with_text(
                           severity = if_abap_behv_message=>severity-success
                           text     = 'Proposal rejected and deleted successfully' )
          ) ).
        ENDIF.

      ENDMETHOD.

      METHOD approve2Proposal.

        DATA: lt_update TYPE TABLE FOR UPDATE ZCDS_Vendor_PaymentRAP.
        DATA: lv_system_date TYPE d,
              lv_system_time TYPE t,
              lv_timezone    TYPE timezone.

        TRY.

            lv_timezone = cl_abap_context_info=>get_user_time_zone( ).

            CONVERT UTCLONG utclong_current( )
                    TIME ZONE lv_timezone
                    INTO DATE lv_system_date
                         TIME lv_system_time.

          CATCH cx_abap_context_info_error INTO DATA(lx_error).

            lv_timezone = 'UTC'.

        ENDTRY.

        CONVERT UTCLONG utclong_current( )
                TIME ZONE lv_timezone
                INTO DATE lv_system_date
                     TIME lv_system_time.

        LOOP AT keys ASSIGNING FIELD-SYMBOL(<ls_key>).
          APPEND VALUE #(
                    Db_Key           = <ls_key>-Db_Key
                    Approval2Status  = abap_true
                    Approval2User    = sy-uname
                    Approval2On      = lv_system_date
                    Approval2Time    = lv_system_time
                    %control-Approval2Status = if_abap_behv=>mk-on
                    %control-Approval2User   = if_abap_behv=>mk-on
                    %control-Approval2On     = if_abap_behv=>mk-on
                    %control-Approval2Time   = if_abap_behv=>mk-on
                  ) TO lt_update.
        ENDLOOP.

        MODIFY ENTITIES OF ZCDS_Vendor_PaymentRAP IN LOCAL MODE
          ENTITY ZCDS_Vendor_PaymentRAP
          UPDATE FIELDS ( Approval2Status Approval2User Approval2On Approval2Time )
          WITH lt_update
          REPORTED DATA(lt_reported)
          FAILED DATA(lt_failed).

        IF lt_failed IS NOT INITIAL.
          failed-zcds_vendor_paymentrap   = CORRESPONDING #( lt_failed-zcds_vendor_paymentrap ).
          reported-zcds_vendor_paymentrap = CORRESPONDING #( lt_reported-zcds_vendor_paymentrap ).
        ELSE.
          reported-zcds_vendor_paymentrap = VALUE #( (
              Db_Key = keys[ 1 ]-Db_Key
              %msg   = new_message_with_text(
                           severity = if_abap_behv_message=>severity-success
                           text     = 'Proposal approved successfully' )
          ) ).
        ENDIF.


      ENDMETHOD.

    ENDCLASS.
