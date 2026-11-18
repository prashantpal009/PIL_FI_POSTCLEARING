@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Value help for approval1'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZVH_APPROVAL1 as select distinct from zvendor_payment 
{
   key id_no,
   supplier,
   supplier_name,
   company_code
}where approval1_user is initial
