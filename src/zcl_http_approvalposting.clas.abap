CLASS zcl_http_approvalposting DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_service_extension.

  PRIVATE SECTION.
    METHODS call_cpi_api
      IMPORTING iv_payload         TYPE string
      RETURNING VALUE(rv_response) TYPE string.

    "==== NEW: Yes Bank CPI call (CC2000) ====
    METHODS call_yesbank_api
      IMPORTING iv_payload         TYPE string
      RETURNING VALUE(rv_response) TYPE string.

    METHODS write_log
      IMPORTING
        iv_idno           TYPE zvendor_payment-id_no
        iv_journal_entry  TYPE belnr_d
        iv_supplier       TYPE i_supplier-supplier
        iv_currency       TYPE i_housebankaccountlinkage-bankaccountcurrency
        iv_invoice_amount TYPE wrbtr
        iv_fiscal_year    TYPE gjahr
        iv_company_code   TYPE bukrs
        iv_amount         TYPE wrbtr
        iv_payment_status TYPE string
        iv_transactionid  TYPE string OPTIONAL
        iv_utrnumber      TYPE c OPTIONAL
        iv_error          TYPE string OPTIONAL.

ENDCLASS.



CLASS ZCL_HTTP_APPROVALPOSTING IMPLEMENTATION.


  METHOD if_http_service_extension~handle_request.

    TYPES: BEGIN OF ty_cpi_response,
             cbx_api_ref_no TYPE string,
             transaction    TYPE string,
           END OF ty_cpi_response.

    TYPES: BEGIN OF ty_yb_data,
             filepaymentstatus TYPE string,
             fileidentifier    TYPE string,
             consentid         TYPE string,
           END OF ty_yb_data,
           BEGIN OF ty_yb_response,
             data TYPE ty_yb_data,
           END OF ty_yb_response.

    TYPES: BEGIN OF ty_item,
             dbkey            TYPE string,
             idno             TYPE zvendor_payment-id_no,
             journalentry     TYPE string,
             FiscleYear       TYPE i_journalentry-fiscalyear,
             companycode      TYPE i_journalentry-companycode,
             supplier         TYPE i_supplier-supplier,
             suppliername     TYPE string,
             housebank        TYPE i_housebankaccountlinkage-housebank,
             HouseBankAccount TYPE I_HouseBankAccountLinkage-HouseBankAccount,
             invoiceamount    TYPE p LENGTH 12 DECIMALS 2,
             amount           TYPE p LENGTH 12 DECIMALS 2,
             currency         TYPE i_housebankaccountlinkage-bankaccountcurrency,
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

    TYPES: BEGIN OF ty_valid_item,
             idno            TYPE zvendor_payment-id_no,
             journal_alpha   TYPE belnr_d,
             journal_raw     TYPE belnr_d,
             FiscleYear      TYPE i_journalentry-fiscalyear,
             companycode     TYPE i_journalentry-companycode,
             supplier        TYPE i_supplier-supplier,
             suppliername    TYPE string,
             housebank       TYPE i_housebankaccountlinkage-housebank,
             housebankacct   TYPE I_HouseBankAccountLinkage-HouseBankAccount,
             invoiceamount   TYPE p LENGTH 12 DECIMALS 2,
             amount          TYPE p LENGTH 12 DECIMALS 2,
             currency        TYPE i_housebankaccountlinkage-bankaccountcurrency,
             beneficiarybank TYPE string,
             bene_acc_no     TYPE string,
             bene_branch     TYPE string,
             debit_acc_no    TYPE string,
             splgl           TYPE i_operationalacctgdocitem-specialglcode,
           END OF ty_valid_item,
           ty_valid_items TYPE STANDARD TABLE OF ty_valid_item WITH EMPTY KEY.

    DATA: ls_payload       TYPE ty_payload,
          lv_json          TYPE string,
          lv_system_date   TYPE d,
          lv_system_time   TYPE t,
          lv_timezone      TYPE timezone,
          lt_errors        TYPE ty_error_list,
          lt_valid         TYPE ty_valid_items,
          lv_success_count TYPE i,
          lv_recovered     TYPE i.

    lv_json = request->get_text( ).

    /ui2/cl_json=>deserialize(
      EXPORTING json = lv_json
      CHANGING  data = ls_payload ).

    IF ls_payload-items IS INITIAL.
      response->set_text( 'No items provided.' ).
      response->set_status( i_code = 400 ).
      RETURN.
    ENDIF.

    lv_timezone = cl_abap_context_info=>get_user_time_zone( ).
    CONVERT UTCLONG utclong_current( )
            TIME ZONE lv_timezone
            INTO DATE lv_system_date
                 TIME lv_system_time.

    DATA(lv_value_date) = |{ lv_system_date+6(2) }/{ lv_system_date+4(2) }/{ lv_system_date(4) }|.

    LOOP AT ls_payload-items ASSIGNING FIELD-SYMBOL(<ls_item>).

      DATA(lv_journal)       = CONV belnr_d( <ls_item>-journalentry ).
      DATA(lv_journal_alpha) = CONV belnr_d( |{ lv_journal ALPHA = IN }| ).

      SELECT transactionid, payment_status
        FROM zbank_pam_log
        WHERE id_no        = @<ls_item>-idno
          AND journal_entry = @lv_journal
          AND companycode   = @<ls_item>-companycode
          AND fiscalyear    = @<ls_item>-FiscleYear
          AND transactionid  <> @space
          AND payment_status <> @space
        ORDER BY PRIMARY KEY
        INTO @DATA(ls_log_prev)
        UP TO 1 ROWS.
      ENDSELECT.

      IF sy-subrc = 0
         AND ls_log_prev-transactionid  IS NOT INITIAL
         AND ls_log_prev-payment_status IS NOT INITIAL.

        UPDATE zvendor_payment
           SET transactionid  = @ls_log_prev-transactionid,
               payment_status = @ls_log_prev-payment_status
         WHERE id_no         = @<ls_item>-idno
           AND journal_entry = @lv_journal_alpha
           AND company_code  = @<ls_item>-companycode
           AND fiscal_year   = @<ls_item>-FiscleYear.

        IF sy-subrc = 0 AND sy-dbcnt > 0.
          COMMIT WORK AND WAIT.
          lv_recovered = lv_recovered + 1.
        ELSE.
          ROLLBACK WORK.
          APPEND VALUE #(
            idno    = <ls_item>-idno
            message = |IdNo { <ls_item>-idno } / JE { lv_journal_alpha }: Already paid (TxnRef { ls_log_prev-transactionid }) but ZVENDOR_PAYMENT sync failed (record missing/key mismatch). Manual update required — do NOT resend.|
          ) TO lt_errors.
        ENDIF.

        CONTINUE.
      ENDIF.

      IF <ls_item>-currency <> 'INR'.
        APPEND VALUE #(
          idno    = <ls_item>-idno
          message = |IdNo { <ls_item>-idno } / JE { lv_journal_alpha }: Currency { <ls_item>-currency } not supported. Only INR allowed.|
        ) TO lt_errors.
        CONTINUE.
      ENDIF.
      SELECT SINGLE transactionid, payment_status
        FROM zvendor_payment
        WHERE id_no        = @<ls_item>-idno
          AND journal_entry = @lv_journal_alpha
          AND company_code  = @<ls_item>-companycode
          AND fiscal_year  = @<ls_item>-FiscleYear
        INTO @DATA(ls_existing).

      IF sy-subrc = 0
        AND ls_existing-transactionid IS NOT INITIAL
        AND ls_existing-payment_status IS NOT INITIAL.

        APPEND VALUE #(
          idno    = <ls_item>-idno
          message = |IdNo { <ls_item>-idno } / JE { lv_journal_alpha } already processed. | &&
                    |TxnID: { ls_existing-transactionid }, | &&
                    |Status: { ls_existing-payment_status }. Duplicate not allowed.|
        ) TO lt_errors.
        CONTINUE.
      ENDIF.

      DATA(lv_supplier_alpha) = |{ <ls_item>-supplier ALPHA = IN }|.

      SELECT SINGLE FROM i_businesspartnerbank AS a
        FIELDS
          a~bankname    AS beneficiarybank,
          a~bankaccount,
          a~banknumber
        WHERE a~businesspartner = @lv_supplier_alpha
        INTO @DATA(bank_payload).

      IF sy-subrc <> 0.
        me->write_log(
          iv_idno           = <ls_item>-idno
          iv_journal_entry  = lv_journal_alpha
          iv_fiscal_year    = <ls_item>-FiscleYear
          iv_company_code   = <ls_item>-companycode
          iv_supplier       = <ls_item>-supplier
          iv_invoice_amount = <ls_item>-invoiceamount
          iv_amount         = <ls_item>-amount
          iv_currency       = <ls_item>-currency
          iv_payment_status = 'FAILED'
          iv_error          = |Bank details not found for supplier { <ls_item>-supplier }| ).

        APPEND VALUE #(
          idno    = <ls_item>-idno
          message = |IdNo { <ls_item>-idno } / JE { lv_journal_alpha }: Bank details not found for supplier { <ls_item>-supplier }.|
        ) TO lt_errors.
        CONTINUE.
      ENDIF.

      SELECT SINGLE FROM i_housebankaccountlinkage AS a
        FIELDS a~bankaccount
        WHERE a~housebank = @<ls_item>-housebank AND a~HouseBankAccount = @<ls_item>-housebankaccount
        INTO @DATA(lv_debit_acc).

      IF sy-subrc <> 0.
        me->write_log(
          iv_idno           = <ls_item>-idno
          iv_journal_entry  = lv_journal_alpha
          iv_fiscal_year    = <ls_item>-FiscleYear
          iv_company_code   = <ls_item>-companycode
          iv_supplier       = <ls_item>-supplier
          iv_invoice_amount = <ls_item>-invoiceamount
          iv_amount         = <ls_item>-amount
          iv_currency       = <ls_item>-currency
          iv_payment_status = 'FAILED'
          iv_error          = |House bank account not found for { <ls_item>-housebank }| ).

        APPEND VALUE #(
          idno    = <ls_item>-idno
          message = |IdNo { <ls_item>-idno } / JE { lv_journal_alpha }: House bank account not found for { <ls_item>-housebank }.|
        ) TO lt_errors.
        CONTINUE.
      ENDIF.
      SELECT SINGLE specialglcode
        FROM i_operationalacctgdocitem
        WHERE companycode        = @<ls_item>-companycode
          AND fiscalyear         = @<ls_item>-FiscleYear
          AND accountingdocument = @lv_journal_alpha
          AND supplier           = @lv_supplier_alpha
        INTO @DATA(lv_splgl).

      APPEND VALUE #(
        idno            = <ls_item>-idno
        journal_alpha   = lv_journal_alpha
        journal_raw     = lv_journal
        FiscleYear      = <ls_item>-FiscleYear
        companycode     = <ls_item>-companycode
        supplier        = <ls_item>-supplier
        suppliername    = <ls_item>-suppliername
        housebank       = <ls_item>-housebank
        housebankacct   = <ls_item>-housebankaccount
        invoiceamount   = <ls_item>-invoiceamount
        amount          = <ls_item>-amount
        currency        = <ls_item>-currency
        beneficiarybank = bank_payload-beneficiarybank
        bene_acc_no     = bank_payload-bankaccount
        bene_branch     = bank_payload-banknumber
        debit_acc_no    = lv_debit_acc
        splgl           = lv_splgl
      ) TO lt_valid.

    ENDLOOP.

    TYPES: BEGIN OF ty_grp_key,
             supplier TYPE i_supplier-supplier,
             idno     TYPE zvendor_payment-id_no,
             solo     TYPE string,
           END OF ty_grp_key.

    DATA lt_keys TYPE STANDARD TABLE OF ty_grp_key WITH EMPTY KEY.

    LOOP AT lt_valid ASSIGNING FIELD-SYMBOL(<lk>).
      APPEND VALUE #(
        supplier = <lk>-supplier
        idno     = <lk>-idno
        solo     = COND #( WHEN <lk>-splgl = 'F'
                           THEN |{ <lk>-idno }_{ <lk>-journal_alpha }|
                           ELSE '' )
      ) TO lt_keys.
    ENDLOOP.

    SORT lt_keys BY supplier idno solo.
    DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING ALL FIELDS.

    LOOP AT lt_keys ASSIGNING FIELD-SYMBOL(<key>).

      DATA lt_grp TYPE ty_valid_items.
      CLEAR lt_grp.

      LOOP AT lt_valid ASSIGNING FIELD-SYMBOL(<lv>)
           WHERE supplier = <key>-supplier
             AND idno     = <key>-idno.

        IF <lv>-splgl <> 'F' AND <key>-solo IS INITIAL.
          APPEND <lv> TO lt_grp.
        ELSEIF <lv>-splgl = 'F'
           AND |{ <lv>-idno }_{ <lv>-journal_alpha }| = <key>-solo.
          APPEND <lv> TO lt_grp.
        ENDIF.

      ENDLOOP.

      IF lt_grp IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA lv_grp_amount TYPE p LENGTH 12 DECIMALS 2.
      lv_grp_amount = 0.
      LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<g>).
        lv_grp_amount = lv_grp_amount + <g>-amount.
      ENDLOOP.

      DATA(ls_head) = lt_grp[ 1 ].

      DATA(lv_amount) = |{ lv_grp_amount DECIMALS = 2 }|.
      REPLACE ALL OCCURRENCES OF ',' IN lv_amount WITH ''.
      CONDENSE lv_amount NO-GAPS.

      DATA: lv_transpayref TYPE string,
            lv_ts          TYPE timestampl,
            lv_ts_str      TYPE string.

      GET TIME STAMP FIELD lv_ts.
      lv_ts_str = |{ lv_ts }|.
      REPLACE ALL OCCURRENCES OF '.' IN lv_ts_str WITH ''.

      IF ls_head-companycode = '2000'.
        lv_transpayref = lv_ts_str(16).
      ELSE.
        lv_transpayref = lv_ts_str(19).
      ENDIF.

      IF ls_head-companycode = '2000'.

        DATA(lv_yb_clearing) = COND string(
            WHEN ls_head-bene_branch(4) = 'YESB' THEN 'Intra Bank Transfer'
            ELSE 'NEFT' ).

        TRY.
            DATA(lv_yb_sys_url) = cl_abap_context_info=>get_system_url( ).
          CATCH cx_abap_context_info_error.
            lv_yb_sys_url = ''.
        ENDTRY.

        DATA(lv_yb_consentid) = SWITCH string( lv_yb_sys_url
          WHEN 'my434946.s4hana.cloud.sap' THEN '5741214'
          WHEN 'my436356.s4hana.cloud.sap' THEN '358600'
          WHEN 'my438594.s4hana.cloud.sap' THEN '5741214'
          ELSE '358600' ).

        DATA(lv_yb_fileidentifier) = |SGNPILyesbank{ lv_ts_str+12(7) }|.
        DATA(lv_yb_secondaryid)    = lv_yb_consentid.

        SELECT SINGLE FROM i_housebankaccountlinkage
          FIELDS bankinternalid, bankaccount
          WHERE companycode      = @ls_head-companycode
            AND housebank        = @ls_head-housebank
            AND housebankaccount = @ls_head-housebankacct
          INTO @DATA(ls_yb_hb).

        IF sy-subrc <> 0 OR ls_yb_hb-bankinternalid IS INITIAL OR ls_yb_hb-bankaccount IS INITIAL.
          LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<ygm>).
            APPEND VALUE #(
              idno    = <ygm>-idno
              message = |IdNo { <ygm>-idno } / JE { <ygm>-journal_alpha }: Yes Bank IFSC/account not maintained for House Bank { ls_head-housebank } / { ls_head-housebankacct }.|
            ) TO lt_errors.
          ENDLOOP.
          CONTINUE.
        ENDIF.

        DATA(lv_yb_debtor_ifsc) = CONV string( ls_yb_hb-bankinternalid ).
        DATA(lv_yb_debtor_acc)  = CONV string( ls_yb_hb-bankaccount ).
        DATA(lv_yb_debtor_name) = ls_head-suppliername.
        DATA(lv_yb_remitteracc) = '000483900000758'.

        DATA(lv_yb_payload) =
            |\{| &&
            |"Data":\{| &&
              |"FileIdentifier":"{ lv_yb_fileidentifier }",| &&
              |"NumberOfTransactions":"1",| &&
              |"ConsentId":"{ lv_yb_consentid }",| &&
              |"ControSum":"{ lv_amount }",| &&
              |"SecondaryIdentification":"{ lv_yb_consentid }",| &&
              |"DomesticPayments":[| &&
                |\{| &&
                  |"ConsentId":"{ lv_yb_consentid }",| &&
                  |"Initiation":\{| &&
                    |"InstructionIdentification":"{ lv_transpayref }",| &&
                    |"ClearingSystemIdentification":"{ lv_yb_clearing }",| &&
                    |"InstructedAmount":\{| &&
                      |"Amount":"{ lv_amount }",| &&
                      |"Currency":"INR"| &&
                    |\},| &&
                    |"DebtorAccount":\{| &&
                      |"SchemeName":"{ lv_yb_debtor_ifsc }",| &&
                      |"Identification":"{ lv_yb_debtor_acc }",| &&
                      |"Name":"PIL PHARMACEUTICALS LTD",| &&
                      |"SecondaryIdentification":"{ lv_yb_secondaryid }"| &&
                    |\},| &&
                    |"CreditorAccount":\{| &&
                      |"SchemeName":"{ ls_head-bene_branch }",| &&
                      |"Identification":"{ ls_head-bene_acc_no }",| &&
                      |"Name":"{ ls_head-suppliername }"| &&
                    |\},| &&
                    |"RemittanceInformation":\{| &&
                      |"Unstructured":\{| &&
                        |"CreditorReferenceInformation":"Go Live",| &&
                        |"RemitterAccount":"{ ls_head-bene_acc_no }"| &&
                      |\}| &&
                    |\}| &&
                  |\},| &&
                  |"Risk":\{| &&
                    |"PaymentContextCode":"BankTransfer",| &&
                    |"DeliveryAddress":\{| &&
                      |"Country":"IN",| &&
                      |"AddressLine":["Haridwar"]| &&
                    |\}| &&
                  |\}| &&
                |\}| &&
              |]| &&
            |\}| &&
            |\}|.

        DATA(lv_yb_raw) = me->call_yesbank_api( iv_payload = lv_yb_payload ).

        DATA: ls_yb_res TYPE ty_yb_response.
        CLEAR ls_yb_res.

        IF lv_yb_raw CS 'ERROR'.
          LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<yge>).
            me->write_log(
              iv_idno           = <yge>-idno
              iv_journal_entry  = <yge>-journal_alpha
              iv_fiscal_year    = <yge>-FiscleYear
              iv_company_code   = <yge>-companycode
              iv_supplier       = <yge>-supplier
              iv_invoice_amount = <yge>-invoiceamount
              iv_amount         = <yge>-amount
              iv_currency       = <yge>-currency
              iv_payment_status = 'FAILED'
              iv_error          = |Yes Bank API Error for Vendor { <yge>-supplier } / IdNo { <yge>-idno } / JE { <yge>-journal_alpha }: { lv_yb_raw }| ).

            APPEND VALUE #(
              idno    = <yge>-idno
              message = |Vendor { <yge>-supplier } / IdNo { <yge>-idno } / JE { <yge>-journal_alpha }: Yes Bank API call failed. { lv_yb_raw }|
            ) TO lt_errors.
          ENDLOOP.
          WAIT UP TO 1 SECONDS.
          CONTINUE.
        ENDIF.

        /ui2/cl_json=>deserialize(
          EXPORTING json = lv_yb_raw
          CHANGING  data = ls_yb_res ).

        IF ls_yb_res-data-filepaymentstatus = 'Received'.

          DATA(lv_yb_status) = ls_yb_res-data-filepaymentstatus.

          LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<yga>).
            me->write_log(
              iv_idno           = <yga>-idno
              iv_journal_entry  = <yga>-journal_alpha
              iv_fiscal_year    = <yga>-FiscleYear
              iv_company_code   = <yga>-companycode
              iv_supplier       = <yga>-supplier
              iv_invoice_amount = <yga>-invoiceamount
              iv_amount         = <yga>-amount
              iv_currency       = <yga>-currency
              iv_utrnumber      = ' '
              iv_payment_status = lv_yb_status
              iv_transactionid  = lv_transpayref ).
          ENDLOOP.

          LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<ygu>).

            UPDATE zvendor_payment
               SET transactionid  = @lv_transpayref,
                   payment_status = @lv_yb_status
             WHERE id_no         = @<ygu>-idno
               AND journal_entry = @<ygu>-journal_alpha
               AND company_code  = @<ygu>-companycode
               AND fiscal_year   = @<ygu>-FiscleYear.

            IF sy-subrc <> 0 OR sy-dbcnt = 0.
              me->write_log(
                iv_idno           = <ygu>-idno
                iv_journal_entry  = <ygu>-journal_alpha
                iv_fiscal_year    = <ygu>-FiscleYear
                iv_company_code   = <ygu>-companycode
                iv_supplier       = <ygu>-supplier
                iv_invoice_amount = <ygu>-invoiceamount
                iv_amount         = <ygu>-amount
                iv_currency       = <ygu>-currency
                iv_transactionid  = lv_transpayref
                iv_payment_status = lv_yb_status
                iv_error          = |CRITICAL: Vendor { <ygu>-supplier } payment RECEIVED (TxnRef { lv_transpayref }), ZVENDOR_PAYMENT UPDATE failed for IdNo { <ygu>-idno } / JE { <ygu>-journal_alpha }. MANUAL UPDATE REQUIRED. DO NOT RE-SEND.| ).

              APPEND VALUE #(
                idno    = <ygu>-idno
                message = |Vendor { <ygu>-supplier } / IdNo { <ygu>-idno } / JE { <ygu>-journal_alpha }: PAYMENT SENT in group (TxnRef { lv_transpayref }) but DB update failed. MANUAL update — do NOT resend.|
              ) TO lt_errors.
            ENDIF.

          ENDLOOP.

          COMMIT WORK AND WAIT.

          LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<ygv>).

            SELECT SINGLE transactionid, payment_status
              FROM zvendor_payment
              WHERE id_no         = @<ygv>-idno
                AND journal_entry = @<ygv>-journal_alpha
                AND company_code  = @<ygv>-companycode
                AND fiscal_year   = @<ygv>-FiscleYear
              INTO @DATA(ls_yb_verify).

            IF sy-subrc = 0
               AND ls_yb_verify-transactionid  = lv_transpayref
               AND ls_yb_verify-payment_status = lv_yb_status.
              lv_success_count = lv_success_count + 1.
            ELSE.
              me->write_log(
                iv_idno           = <ygv>-idno
                iv_journal_entry  = <ygv>-journal_alpha
                iv_fiscal_year    = <ygv>-FiscleYear
                iv_company_code   = <ygv>-companycode
                iv_supplier       = <ygv>-supplier
                iv_invoice_amount = <ygv>-invoiceamount
                iv_amount         = <ygv>-amount
                iv_currency       = <ygv>-currency
                iv_transactionid  = lv_transpayref
                iv_payment_status = lv_yb_status
                iv_error          = |CRITICAL: Vendor { <ygv>-supplier } payment RECEIVED (TxnRef { lv_transpayref }) but ZVENDOR_PAYMENT verify failed for IdNo { <ygv>-idno } / JE { <ygv>-journal_alpha }. MANUAL UPDATE REQUIRED. DO NOT RE-SEND.| ).

              APPEND VALUE #(
                idno    = <ygv>-idno
                message = |Vendor { <ygv>-supplier } / IdNo { <ygv>-idno } / JE { <ygv>-journal_alpha }: PAYMENT SENT (TxnRef { lv_transpayref }) but ZVENDOR_PAYMENT not confirmed. MANUAL update — do NOT resend.|
              ) TO lt_errors.
            ENDIF.

          ENDLOOP.

        ELSE.

          LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<ygn>).
            me->write_log(
              iv_idno           = <ygn>-idno
              iv_journal_entry  = <ygn>-journal_alpha
              iv_fiscal_year    = <ygn>-FiscleYear
              iv_company_code   = <ygn>-companycode
              iv_supplier       = <ygn>-supplier
              iv_invoice_amount = <ygn>-invoiceamount
              iv_amount         = <ygn>-amount
              iv_currency       = <ygn>-currency
              iv_utrnumber      = ' '
              iv_payment_status = 'FAILED'
              iv_error          = |Yes Bank: payment not received for Vendor { <ygn>-supplier } / IdNo { <ygn>-idno } / JE { <ygn>-journal_alpha }: { lv_yb_raw }| ).

            APPEND VALUE #(
              idno    = <ygn>-idno
              message = |Vendor { <ygn>-supplier } / IdNo { <ygn>-idno } / JE { <ygn>-journal_alpha }: Payment not accepted by Yes Bank. { lv_yb_raw }|
            ) TO lt_errors.
          ENDLOOP.

        ENDIF.

        WAIT UP TO 1 SECONDS.
        CONTINUE.

      ENDIF.

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

      DATA(lv_transfer_type) = COND string(
          WHEN ls_head-bene_branch(4) = 'HDFC' THEN 'Intra Bank Transfer'
          ELSE 'NEFT' ).

*          DATA(lv_debit_org_acc) = SWITCH string( ls_head-companycode
*        WHEN '1000' THEN '00500340000261'
*        WHEN '2000' THEN '000483900000758'
*        ELSE '' ).


      DATA(lv_cpi_payload) =
          |\{| &&
          |"LOGIN_ID":"{ loginid }",| &&
          |"INPUT_GCIF":"{ inputgcip }",| &&
          |"TRANSFER_TYPE_DESC":"{ lv_transfer_type }",| &&
          |"BENE_BANK":"{ ls_head-beneficiarybank }",| &&
          |"INPUT_DEBIT_AMOUNT":"{ lv_amount }",| &&
          |"INPUT_VALUE_DATE":"{ lv_value_date }",| &&
          |"TRANSACTION_TYPE":"SINGLE",| &&
          |"INPUT_DEBIT_ORG_ACC_NO":"{ ls_head-debit_acc_no }",| &&
*          |"INPUT_DEBIT_ORG_ACC_NO":"{ lv_debit_org_acc }",| &&
          |"INPUT_BUSINESS_PROD":"VENDBUS01",| &&
          |"BENE_ID":"",| &&
          |"BENE_ACC_NAME":"{ ls_head-suppliername }",| &&
          |"BENE_ACC_NO":"{ ls_head-bene_acc_no }",| &&
          |"BENE_TYPE":"ADHOC",| &&
          |"BENE_BRANCH":"{ ls_head-bene_branch }",| &&
          |"BENE_IDN_CODE":"{ ls_head-bene_branch }",| &&
          |"EMAIL_ADDR_VIEW":"payables@pilindia.in",| &&
          |"PAYMENT_REF_NO":"{ lv_transpayref }",| &&
          |"ADDL_EMAIL":""| &&
          |\}|.

      DATA(lv_raw_response) = me->call_cpi_api( iv_payload = lv_cpi_payload ).

      DATA: ls_cpi_res TYPE ty_cpi_response.
      CLEAR ls_cpi_res.

      IF lv_raw_response CS 'ERROR'.
        LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<ge>).
          me->write_log(
            iv_idno           = <ge>-idno
            iv_journal_entry  = <ge>-journal_alpha
            iv_fiscal_year    = <ge>-FiscleYear
            iv_company_code   = <ge>-companycode
            iv_supplier       = <ge>-supplier
            iv_invoice_amount = <ge>-invoiceamount
            iv_amount         = <ge>-amount
            iv_currency       = <ge>-currency
            iv_payment_status = 'FAILED'
            iv_error          = |CPI API Error for Vendor { <ge>-supplier } / IdNo { <ge>-idno } / JE { <ge>-journal_alpha }: { lv_raw_response }| ).

          APPEND VALUE #(
            idno    = <ge>-idno
            message = |Vendor { <ge>-supplier } / IdNo { <ge>-idno } / JE { <ge>-journal_alpha }: CPI API call failed. { lv_raw_response }|
          ) TO lt_errors.
        ENDLOOP.
        WAIT UP TO 1 SECONDS.
        CONTINUE.
      ENDIF.

      /ui2/cl_json=>deserialize(
        EXPORTING json = lv_raw_response
        CHANGING  data = ls_cpi_res ).

      IF ls_cpi_res-transaction = 'Accepted'.

        LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<ga>).
          me->write_log(
            iv_idno           = <ga>-idno
            iv_journal_entry  = <ga>-journal_alpha
            iv_fiscal_year    = <ga>-FiscleYear
            iv_company_code   = <ga>-companycode
            iv_supplier       = <ga>-supplier
            iv_invoice_amount = <ga>-invoiceamount
            iv_amount         = <ga>-amount
            iv_currency       = <ga>-currency
            iv_utrnumber      = ' '
            iv_payment_status = ls_cpi_res-transaction
            iv_transactionid  = lv_transpayref ).
        ENDLOOP.

        DATA lv_grp_all_ok TYPE abap_bool.
        lv_grp_all_ok = abap_true.

        LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<gu>).

          UPDATE zvendor_payment
             SET transactionid  = @lv_transpayref,
                 payment_status = @ls_cpi_res-transaction
           WHERE id_no         = @<gu>-idno
             AND journal_entry = @<gu>-journal_alpha
             AND company_code  = @<gu>-companycode
             AND fiscal_year   = @<gu>-FiscleYear.

          IF sy-subrc <> 0 OR sy-dbcnt = 0.
            lv_grp_all_ok = abap_false.

            me->write_log(
              iv_idno           = <gu>-idno
              iv_journal_entry  = <gu>-journal_alpha
              iv_fiscal_year    = <gu>-FiscleYear
              iv_company_code   = <gu>-companycode
              iv_supplier       = <gu>-supplier
              iv_invoice_amount = <gu>-invoiceamount
              iv_amount         = <gu>-amount
              iv_currency       = <gu>-currency
              iv_transactionid  = lv_transpayref
              iv_payment_status = ls_cpi_res-transaction
              iv_error          = |CRITICAL: Vendor { <gu>-supplier } payment ACCEPTED (TxnRef { lv_transpayref },ZVENDOR_PAYMENT UPDATE failed for IdNo { <gu>-idno } / JE { <gu>-journal_alpha }. MANUAL UPDATE REQUIRED. DO NOT RE-SEND.| ).

            APPEND VALUE #(
              idno    = <gu>-idno
              message = |Vendor { <gu>-supplier } / IdNo { <gu>-idno } / JE { <gu>-journal_alpha }: PAYMENT SENT in group (TxnRef { lv_transpayref }) but DB update failed. MANUAL update — do NOT resend.|
            ) TO lt_errors.
          ENDIF.

        ENDLOOP.

        COMMIT WORK AND WAIT.
        LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<gv>).

          SELECT SINGLE transactionid, payment_status
            FROM zvendor_payment
            WHERE id_no         = @<gv>-idno
              AND journal_entry = @<gv>-journal_alpha
              AND company_code  = @<gv>-companycode
              AND fiscal_year   = @<gv>-FiscleYear
            INTO @DATA(ls_verify).

          IF sy-subrc = 0
             AND ls_verify-transactionid  = lv_transpayref
             AND ls_verify-payment_status = ls_cpi_res-transaction.
            lv_success_count = lv_success_count + 1.
          ELSE.
            me->write_log(
              iv_idno           = <gv>-idno
              iv_journal_entry  = <gv>-journal_alpha
              iv_fiscal_year    = <gv>-FiscleYear
              iv_company_code   = <gv>-companycode
              iv_supplier       = <gv>-supplier
              iv_invoice_amount = <gv>-invoiceamount
              iv_amount         = <gv>-amount
              iv_currency       = <gv>-currency
              iv_transactionid  = lv_transpayref
              iv_payment_status = ls_cpi_res-transaction
              iv_error          = |CRITICAL: Vendor { <gv>-supplier } payment ACCEPTED (TxnRef { lv_transpayref }) but ZVENDOR_PAYMENT verify failed for IdNo { <gv>-idno } / JE { <gv>-journal_alpha }. MANUAL UPDATE REQUIRED. DO NOT RE-SEND.| ).

            APPEND VALUE #(
              idno    = <gv>-idno
              message = |Vendor { <gv>-supplier } / IdNo { <gv>-idno } / JE { <gv>-journal_alpha }: PAYMENT SENT (TxnRef { lv_transpayref }) but ZVENDOR_PAYMENT not confirmed. MANUAL update — do NOT resend.|
            ) TO lt_errors.
          ENDIF.

        ENDLOOP.
      ELSE.

        LOOP AT lt_grp ASSIGNING FIELD-SYMBOL(<gn>).
          me->write_log(
            iv_idno           = <gn>-idno
            iv_journal_entry  = <gn>-journal_alpha
            iv_fiscal_year    = <gn>-FiscleYear
            iv_company_code   = <gn>-companycode
            iv_supplier       = <gn>-supplier
            iv_invoice_amount = <gn>-invoiceamount
            iv_amount         = <gn>-amount
            iv_currency       = <gn>-currency
            iv_utrnumber      = ' '
            iv_payment_status = 'FAILED'
            iv_error          = |Transaction not accepted for Vendor { <gn>-supplier } / IdNo { <gn>-idno } / JE { <gn>-journal_alpha }: { lv_raw_response }| ).

          APPEND VALUE #(
            idno    = <gn>-idno
            message = |Vendor { <gn>-supplier } / IdNo { <gn>-idno } / JE { <gn>-journal_alpha }: Payment not accepted by bank. { lv_raw_response }|
          ) TO lt_errors.
        ENDLOOP.

      ENDIF.

      WAIT UP TO 1 SECONDS.

    ENDLOOP.

    IF lt_errors IS NOT INITIAL.

      DATA(lv_total)  = lines( ls_payload-items ).
      DATA(lv_failed) = lines( lt_errors ).

      DATA(lv_error_text) =
        |Processing Summary: { lv_success_count } sent, { lv_recovered } recovered/synced, | &&
        |{ lv_failed } need attention (of { lv_total } total).\n\n|.

      LOOP AT lt_errors ASSIGNING FIELD-SYMBOL(<ls_err>).
        lv_error_text = lv_error_text && |• { <ls_err>-message }\n|.
      ENDLOOP.

      IF lv_success_count = 0 AND lv_recovered = 0.
        response->set_text( lv_error_text ).
        response->set_status( i_code = 400 ).
      ELSE.
        response->set_text( lv_error_text ).
        response->set_status( i_code = 207 ).
      ENDIF.

    ELSE.
      response->set_text(
        |All { lines( ls_payload-items ) } document(s) processed successfully | &&
        |({ lv_success_count } sent, { lv_recovered } recovered/synced).| ).
      response->set_status( i_code = 200 ).
    ENDIF.

  ENDMETHOD.


  METHOD call_cpi_api.

    TRY.
        DATA(lv_sys_url) = cl_abap_context_info=>get_system_url( ).

        DATA(lv_cpi_url) = SWITCH string( lv_sys_url
   WHEN 'my434946.s4hana.cloud.sap' THEN
     'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/DEV/HDFC_Payment'
   WHEN 'my436356.s4hana.cloud.sap' THEN
     'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/DEV/HDFC_Payment'
   WHEN 'my438594.s4hana.cloud.sap' THEN
     'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/HDFC/Payment'
   ELSE
     THROW cx_web_message_error( ) ).

        DATA(lv_username) = SWITCH string( lv_sys_url
   WHEN 'my434946.s4hana.cloud.sap' THEN
     'sb-e0695cf3-8f56-48f1-b1f8-49e7f90f4762!b40612|it-rt-pil-btp-prd-environment-bbojexhh!b148'
   WHEN 'my436356.s4hana.cloud.sap' THEN
     'sb-e0695cf3-8f56-48f1-b1f8-49e7f90f4762!b40612|it-rt-pil-btp-prd-environment-bbojexhh!b148'
   WHEN 'my438594.s4hana.cloud.sap' THEN
     'sb-e0695cf3-8f56-48f1-b1f8-49e7f90f4762!b40612|it-rt-pil-btp-prd-environment-bbojexhh!b148'
   ELSE `` ).

        DATA(lv_password) = SWITCH string( lv_sys_url
     WHEN 'my434946.s4hana.cloud.sap' THEN
       'b6a16460-0167-4c38-9338-66a82cd5e5ae$NqrKEUEBeHMklthaW_AWAoyJUyiiHzDWGyWgf6XtIk8='
     WHEN 'my436356.s4hana.cloud.sap' THEN
       'b6a16460-0167-4c38-9338-66a82cd5e5ae$NqrKEUEBeHMklthaW_AWAoyJUyiiHzDWGyWgf6XtIk8='
     WHEN 'my438594.s4hana.cloud.sap' THEN
       'b6a16460-0167-4c38-9338-66a82cd5e5ae$NqrKEUEBeHMklthaW_AWAoyJUyiiHzDWGyWgf6XtIk8='
     ELSE `` ).

        DATA(lo_dest)   = cl_http_destination_provider=>create_by_url( lv_cpi_url ).
        DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination( lo_dest ).
        DATA(lo_req)    = lo_client->get_http_request( ).
        lo_req->set_authorization_basic( i_username = lv_username
                                      i_password = lv_password ).

        lo_client->get_http_request( )->set_header_field(
          i_name  = 'Content-Type'
          i_value = 'application/json' ).

        lo_client->get_http_request( )->set_text( i_text = iv_payload ).

        DATA(lo_response) = lo_client->execute( i_method = if_web_http_client=>post ).
        rv_response = lo_response->get_text( ).

      CATCH cx_web_http_client_error
            cx_http_dest_provider_error INTO DATA(lx_err).
        rv_response = |ERROR: { lx_err->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.


  METHOD call_yesbank_api.

    TRY.
        DATA(lv_sys_url) = cl_abap_context_info=>get_system_url( ).

        DATA(lv_yb_url) = SWITCH string( lv_sys_url
   WHEN 'my434946.s4hana.cloud.sap' THEN
     'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/UAT/YesBank/Payment'  " TODO PRD url
   WHEN 'my436356.s4hana.cloud.sap' THEN
     'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/UAT/YesBank/Payment'  " TODO QA  url
   WHEN 'my438594.s4hana.cloud.sap' THEN
     'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/UAT/YesBank/Payment'
   ELSE
     'https://pil-btp-prd-environment-bbojexhh.it-cpi021-rt.cfapps.in30.hana.ondemand.com/http/UAT/YesBank/Payment' ).

        " TODO: replace with real Yes Bank iFlow credentials (SWITCH by system)
        DATA(lv_username) = SWITCH string( lv_sys_url
   WHEN 'my434946.s4hana.cloud.sap' THEN
     'sb-e0695cf3-8f56-48f1-b1f8-49e7f90f4762!b40612|it-rt-pil-btp-prd-environment-bbojexhh!b148'
   WHEN 'my436356.s4hana.cloud.sap' THEN
     'sb-e0695cf3-8f56-48f1-b1f8-49e7f90f4762!b40612|it-rt-pil-btp-prd-environment-bbojexhh!b148'
   WHEN 'my438594.s4hana.cloud.sap' THEN
     'sb-e0695cf3-8f56-48f1-b1f8-49e7f90f4762!b40612|it-rt-pil-btp-prd-environment-bbojexhh!b148'
   ELSE `` ).

        DATA(lv_password) = SWITCH string( lv_sys_url
     WHEN 'my434946.s4hana.cloud.sap' THEN
       'b6a16460-0167-4c38-9338-66a82cd5e5ae$NqrKEUEBeHMklthaW_AWAoyJUyiiHzDWGyWgf6XtIk8='
     WHEN 'my436356.s4hana.cloud.sap' THEN
       'b6a16460-0167-4c38-9338-66a82cd5e5ae$NqrKEUEBeHMklthaW_AWAoyJUyiiHzDWGyWgf6XtIk8='
     WHEN 'my438594.s4hana.cloud.sap' THEN
       'b6a16460-0167-4c38-9338-66a82cd5e5ae$NqrKEUEBeHMklthaW_AWAoyJUyiiHzDWGyWgf6XtIk8='
     ELSE `` ).

        DATA(lo_dest)   = cl_http_destination_provider=>create_by_url( lv_yb_url ).
        DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination( lo_dest ).
        DATA(lo_req)    = lo_client->get_http_request( ).
        lo_req->set_authorization_basic( i_username = lv_username
                                         i_password = lv_password ).

        lo_client->get_http_request( )->set_header_field(
          i_name  = 'Content-Type'
          i_value = 'application/json' ).

        lo_client->get_http_request( )->set_text( i_text = iv_payload ).

        DATA(lo_response) = lo_client->execute( i_method = if_web_http_client=>post ).
        rv_response = lo_response->get_text( ).

      CATCH cx_web_http_client_error
            cx_http_dest_provider_error INTO DATA(lx_err).
        rv_response = |ERROR: { lx_err->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.


  METHOD write_log.
    DATA: ls_log TYPE zbank_pam_log.

    ls_log-client               = sy-mandt.
    ls_log-id_no                = iv_idno.
    ls_log-journal_entry        = iv_journal_entry.
    ls_log-fiscalyear           = iv_fiscal_year.
    ls_log-companycode          = iv_company_code.
    ls_log-supplier             = iv_supplier.
    ls_log-invoice_amount       = iv_invoice_amount.
    ls_log-amount_proposal      = iv_amount.
    ls_log-transaction_currency = iv_currency.
    ls_log-transactionid        = iv_transactionid.
    ls_log-payment_status       = iv_payment_status.
    ls_log-utrnumber            = iv_utrnumber.
    ls_log-error                = iv_error.

    INSERT zbank_pam_log FROM @ls_log.
    IF sy-subrc = 0.
      COMMIT WORK.
    ENDIF.

  ENDMETHOD.
ENDCLASS.
