@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Value Help for Approval Report'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZVH_ApprovalReport as select distinct from zvendor_payment 
{
   key id_no,
   company_code
}
