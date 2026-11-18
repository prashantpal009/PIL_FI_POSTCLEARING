@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'CDS For Invoice Paid Sum'

define view entity ZFI_InvoicePaidSum
  as select from I_AccountingDocumentJournal( P_Language: $session.system_language ) as a
    inner join   I_OperationalAcctgDocItem                                           as b on  b.AccountingDocument     = a.InvoiceReference
                                                                                          and b.AccountingDocumentItem = a.InvoiceItemReference
                                                                                          and b.CompanyCode    = a.CompanyCode
                                                                                          and b.FiscalYear  = a.InvoiceReferenceFiscalYear
{
  key a.CompanyCode,
  key a.InvoiceReference,
  key a.InvoiceReferenceFiscalYear,
  key a.Supplier,
      b.AmountInTransactionCurrency                             as InvoiceAmount,
      cast( sum( a.DebitAmountInTransCrcy ) as abap.dec(23,2) ) as PaidAmount,

      case
         when b.AmountInTransactionCurrency < 0
             then cast(
                 abs( b.AmountInTransactionCurrency )
                 - sum( a.DebitAmountInTransCrcy )
                 as abap.dec(23,2)
             )
         else
             cast(
                 b.AmountInTransactionCurrency
                 + sum( a.DebitAmountInTransCrcy )
                 as abap.dec(23,2)
             )
      end                                                       as AmountToBePaid,

      a.TransactionCurrency
}
where
      a.FinancialAccountType = 'K'
  and a.Ledger               = '0L'
  and a.InvoiceReference     is not initial
  and a.ClearingAccountingDocument is initial
group by
  a.CompanyCode,
  a.InvoiceReference,
  a.Supplier,
  //    a.AccountingDocument,
  b.AmountInTransactionCurrency,
  a.InvoiceReferenceFiscalYear,
  a.TransactionCurrency   

//
//@AbapCatalog.viewEnhancementCategory: [#NONE]
//@AccessControl.authorizationCheck: #NOT_REQUIRED
//@EndUserText.label: 'CDS For Invoice Paid Records'
//
//define view entity ZFI_InvoicePaidSum
//  as select from I_AccountingDocumentJournal( P_Language: $session.system_language ) as a
//    inner join   I_OperationalAcctgDocItem                                           as b on  b.AccountingDocument     = a.InvoiceReference
//                                                                                          and b.AccountingDocumentItem = a.InvoiceItemReference
//                                                                                          and b.CompanyCode    = a.CompanyCode
//                                                                                          and b.FiscalYear             = a.InvoiceReferenceFiscalYear
//{
//  key a.CompanyCode,
//  key a.AccountingDocument,
//  key a.AccountingDocumentItem,
//  key a.FiscalYear,
//  key a.InvoiceReference,
//  key a.InvoiceReferenceFiscalYear,
//  key a.InvoiceItemReference,
//      a.Supplier,
//      b.AmountInTransactionCurrency                       as InvoiceAmount,
//      cast( a.DebitAmountInTransCrcy as abap.dec(23,2) )  as PaidAmount,
//
//      case
//        when b.AmountInTransactionCurrency < 0
//          then cast(
//                 abs( b.AmountInTransactionCurrency )
//                 - a.DebitAmountInTransCrcy
//                 as abap.dec(23,2)
//               )
//        else
//          cast(
//            b.AmountInTransactionCurrency
//            + a.DebitAmountInTransCrcy
//            as abap.dec(23,2)
//          )
//      end                                                 as AmountToBePaid,
//
//      a.TransactionCurrency,
//      a.PostingDate,
//      a.ClearingAccountingDocument
//}
//where
//      a.FinancialAccountType         = 'K'
//  and a.Ledger                       = '0L'
//  and a.InvoiceReference             is not initial
//  and a.ClearingAccountingDocument   is initial
