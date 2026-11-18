@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'cds for i_operational document cds'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZFI_IOperationalDoc as select from I_OperationalAcctgDocItem {
  key CompanyCode,
    key AccountingDocument,
    key FiscalYear,
    key AccountingDocumentItem,
    cast( '' as abap.char(10) ) as IdNo,
    substring(OriginalReferenceDocument, 1, 10) as OriginalReferenceDocument
}
