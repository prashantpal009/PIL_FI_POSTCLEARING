@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Value help for Send Payment'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZVH_SendPayment as select distinct from zvendor_payment
{
    key id_no
//   supplier,
//   supplier_name,
//   company_code
}where utrnumber is initial and approval1_user is not initial and approval2_user is not initial
