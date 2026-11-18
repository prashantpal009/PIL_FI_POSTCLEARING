@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Value help for currency and Vendor'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZOpenVendorVH as select distinct from I_OperationalAcctgDocItem as a
left outer join I_Supplier as b on a.Supplier = b.Supplier
{
    key a.CompanyCode,
    key a.Supplier,
    a.FinancialAccountType,
    b.SupplierName,
    a.TransactionCurrency

} where a.ClearingJournalEntry is initial and a.FinancialAccountType = 'K'
