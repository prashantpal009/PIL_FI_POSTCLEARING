@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Value help for Invoice Posting'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZVH_InvoicePosting as select distinct from zvendor_payment
{
    key id_no,
    company_code,
   supplier,
   supplier_name 
}where post_status is initial and approval1_user is not initial and approval2_user is not initial
