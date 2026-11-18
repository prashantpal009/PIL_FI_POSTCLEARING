CLASS zcl_test DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_oo_adt_classrun .
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_TEST IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.

  DATA idno TYPE zvendor_payment-id_no.
  data jlno type zvendor_payment-journal_entry.
  data fiscleyear type zvendor_payment-fiscal_year.
  data companycode type zvendor_payment-company_code.

  idno = '12345'.
  IF idno IS INITIAL.
    out->write( 'id_no empty hai, delete nahi kiya.' ).
    RETURN.
  ENDIF.


  DELETE FROM zvendor_payment WHERE id_no = @idno and journal_entry = @jlno and fiscal_year = @fiscleyear and company_code = @companycode.

  IF sy-subrc = 0.
    out->write( |Records deleted for id_no: { idno }| ).
  ELSE.
    out->write( |Koi record nahi mila id_no: { idno }| ).
  ENDIF.

DATA lt_data TYPE TABLE OF zbankproficenter.

    lt_data = VALUE #(
      ( client = sy-mandt company_code = '1000' house_bank = 'HDFC1' house_bank_acct = 'HD117' outgoing_gl_account = '0002040000' profit_center = '0000001002' )
      ( client = sy-mandt company_code = '1000' house_bank = 'HDFC2' house_bank_acct = 'HD107' outgoing_gl_account = '0002040000' profit_center = '0000001003' )
      ( client = sy-mandt company_code = '1000' house_bank = 'HDFC5' house_bank_acct = 'HD602' outgoing_gl_account = '0002040000' profit_center = '0000001001' )
      ( client = sy-mandt company_code = '1000' house_bank = 'HDFC7' house_bank_acct = 'HD12'  outgoing_gl_account = '0002040000' profit_center = '0000001004' )
      ( client = sy-mandt company_code = '2000' house_bank = 'YESB1' house_bank_acct = 'YE883' outgoing_gl_account = '0002040000' profit_center = '0000002001' )
    ).

    MODIFY zbankproficenter FROM TABLE @lt_data.

    IF sy-subrc = 0.
      COMMIT WORK.
      out->write( |{ lines( lt_data ) } records inserted/updated successfully.| ).
    ELSE.
      ROLLBACK WORK.
      out->write( 'Insert failed.' ).
    ENDIF.

      data sona type c length 1 .

IF sona = 'K'.
  DELETE FROM zbankproficenter.
  IF sy-subrc = 0.
    COMMIT WORK.
  ENDIF.
endIF.


DATA flag          TYPE c LENGTH 1.
  DATA transitionid  TYPE zvendor_payment-transactionid.
  DATA paymentstatus TYPE zvendor_payment-payment_status.

  IF flag = 'K'.
    UPDATE zvendor_payment
      SET transactionid  = @transitionid,
          payment_status = @paymentstatus
      WHERE id_no = @idno AND journal_entry = @jlno.
  ENDIF.
  DATA slno       TYPE zbankcollection-sl_no.
  DATA docdate    TYPE zbankcollection-document_date.
  DATA amount     TYPE zbankcollection-amount.

  IF flag = 'G'.
    DELETE FROM zbankcollection
      WHERE sl_no         = @slno
         OR document_date = @docdate
         OR ( sl_no = @slno AND amount = @amount ).

    IF sy-subrc = 0.
      COMMIT WORK.
      out->write( 'zbankcollection records deleted.' ).
    ELSE.
      out->write( 'No matching zbankcollection record found.' ).
    ENDIF.
  ENDIF.

  IF flag = 'C'.
    UPDATE zbankcollection
      SET amount        = @amount
      WHERE sl_no         = @slno
         OR document_date = @docdate
         OR ( sl_no = @slno AND amount = @amount ).

    IF sy-subrc = 0.
      COMMIT WORK.
      out->write( 'zbankcollection records updated.' ).
    ELSE.
      out->write( 'No matching zbankcollection record found for update.' ).
    ENDIF.
  ENDIF.

  ENDMETHOD.
ENDCLASS.
