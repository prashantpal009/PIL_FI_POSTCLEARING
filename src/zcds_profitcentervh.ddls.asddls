@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Value Help For Profit Center'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZCDS_ProfitCenterVH as select distinct from ZFI_VendorOpenReport as a
{
key a.ProfitCenter
} where a.ProfitCenter is not initial
