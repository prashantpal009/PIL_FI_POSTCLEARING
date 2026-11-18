CLASS zcl_http_manualutr DEFINITION
  PUBLIC
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_http_service_extension .
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_HTTP_MANUALUTR IMPLEMENTATION.


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

    DATA lt_update TYPE STANDARD TABLE OF zvendor_payment.

    DATA lv_utrvalue TYPE string.

    LOOP AT ls_payload-items ASSIGNING FIELD-SYMBOL(<ls_item>).
      DATA lv_je TYPE c LENGTH 10.
      lv_je = |{ <ls_item>-journalentry ALPHA = IN }|.

      lv_utrvalue = |{ lv_je }{ <ls_item>-companycode }{ <ls_item>-fiscalyear }|.

      UPDATE zvendor_payment
        SET utrnumber = @lv_utrvalue
        WHERE journal_entry = @lv_je
          AND company_code  = @<ls_item>-companycode
          AND fiscal_year   = @<ls_item>-fiscalyear
          AND id_no         = @<ls_item>-idno.

      DATA(lv_subrc)  = sy-subrc.
      DATA(lv_dbcnt)  = sy-dbcnt.

      IF lv_subrc = 0 AND lv_dbcnt > 0.
        lv_success_count = lv_success_count + 1.
      ELSE.
        lv_fail_count = lv_fail_count + 1.
        lv_messages = lv_messages
          && |Update failed for ID No: { <ls_item>-idno } (JE: { lv_je })|
          && cl_abap_char_utilities=>newline.
      ENDIF.

    ENDLOOP.

    IF lv_success_count > 0.
      COMMIT WORK AND WAIT.
    ENDIF.

    lv_result = |UTR Update Completed. Success: { lv_success_count }, Failed: { lv_fail_count }|.
    IF lv_messages IS NOT INITIAL.
      lv_result = lv_result && cl_abap_char_utilities=>newline && lv_messages.
    ENDIF.

    response->set_text( lv_result ).
    response->set_status( i_code = 200 ).

  ENDMETHOD.
ENDCLASS.
