@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Value help for approval2'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZVH_APPROVAL2 as select distinct from zvendor_payment 
{
key id_no,
supplier,
supplier_name,
company_code
    
}where approval2_user is initial and approval1_user is not initial
