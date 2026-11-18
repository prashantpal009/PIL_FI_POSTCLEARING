CLASS zcl_uniqidgen DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    CLASS-METHODS getCID RETURNING VALUE(cid) TYPE abp_behv_cid.
  PROTECTED SECTION.
ENDCLASS.



CLASS ZCL_UNIQIDGEN IMPLEMENTATION.


  METHOD getCID.
    TRY.
        cid = to_upper( cl_uuid_factory=>create_system_uuid( )->create_uuid_x16( ) ).
      CATCH cx_uuid_error.
        ASSERT 1 = 0.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
