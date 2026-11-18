@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Cds for Vendor Onpen Items'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZFI_VendorOpenReport
  as select distinct from I_OperationalAcctgDocItem   as a

    left outer join       ZFI_IOperationalDoc         as helper   on  a.CompanyCode            = helper.CompanyCode
                                                                  and a.AccountingDocument     = helper.AccountingDocument
                                                                  and a.FiscalYear             = helper.FiscalYear
                                                                  and a.AccountingDocumentItem = helper.AccountingDocumentItem


    left outer join       I_AccountingDocumentJournal(
                          P_Language: $session.system_language
                          )                           as b        on  a.CompanyCode            = b.CompanyCode
                                                                  and a.AccountingDocument     = b.AccountingDocument
                                                                  and a.FiscalYear             = b.FiscalYear
                                                                  and a.AccountingDocumentItem = b.AccountingDocumentItem
                                                                  and b.Ledger                 = '0L'

    left outer join       I_PurchaseOrderHistoryAPI01 as po       on  helper.OriginalReferenceDocument = po.PurchasingHistoryDocument
                                                                  and po.PurchasingHistoryCategory     = 'Q'

    left outer join       I_PurchaseOrderHistoryAPI01 as po_grn   on  po.PurchaseOrder                 = po_grn.PurchaseOrder
                                                                  and po.PurchaseOrderItem             = po_grn.PurchaseOrderItem
                                                                  and po.ReferenceDocument             = po_grn.ReferenceDocument
                                                                  and po.ReferenceDocumentItem         = po_grn.ReferenceDocumentItem
                                                                  and po.ReferenceDocumentFiscalYear   = po_grn.ReferenceDocumentFiscalYear
                                                                  and po_grn.PurchasingHistoryCategory = 'E'
                                                                  and (
                                                                     po_grn.GoodsMovementType          = '101'
                                                                     or po_grn.GoodsMovementType       = '105'
                                                                   )

    left outer join       ZCDS_ConsumptionQty         as cons     on  po_grn.Plant    = cons.Plant
                                                                  and po_grn.Material = cons.Material
                                                                  and po_grn.Batch    = cons.Batch

    left outer join       I_Product                   as PROD     on po.Material = PROD.Product
    left outer join       I_ProductText               as prodtext on PROD.Product = prodtext.Product and prodtext.Language = $session.system_language

    left outer join       I_Supplier                  as c        on a.Supplier = c.Supplier

    left outer join       ZCDS_Vendor_PaymentRAP      as _Saved   on  a.AccountingDocument = _Saved.JournalEntry
                                                                  and b.ProfitCenter       = _Saved.ProfitCenter
                                                                  and a.FiscalYear         = _Saved.FiscalYear
                                                                  and a.CompanyCode        = _Saved.CompanyCode

    left outer join       ZFI_InvoicePaidSum          as _payment on  a.CompanyCode        = _payment.CompanyCode
                                                                  and a.AccountingDocument = _payment.InvoiceReference
                                                                  and a.FiscalYear         = _payment.InvoiceReferenceFiscalYear


{
  key a.CompanyCode,
  key a.AccountingDocument                                                                                          as journalEntry,
  key a.FiscalYear,
  key a.AccountingDocumentItem,
      a.AccountingDocumentType                                                                                      as JournalEntryType,
      a.ClearingJournalEntry,
      a.InvoiceReference,
      a.InvoiceReferenceFiscalYear,
      a.BusinessPlace,
      a.OriginalReferenceDocument,
      a.DocumentDate                                                                                                as InvoiceDate,
      a.PostingDate,
      dats_days_between(a.DueCalculationBaseDate, a.NetDueDate)                                                     as Paymentdays,
      a.NetDueDate                                                                                                  as NetDueDate,
      a._JournalEntry.DocumentReferenceID                                                                           as invoice_No,
      @Semantics.amount.currencyCode: 'TransactionCurrency'
      a.AmountInTransactionCurrency                                                                                 as invoice_Value,
      a.PostingKey,
      a.FinancialAccountType,
      a.Supplier,
      a.FiscalPeriod,
      a.SpecialGLCode,
      case
          when a.AccountingDocumentType = 'RE' then
              substring(a.OriginalReferenceDocument, 1, 10)
          else
            cast( '' as abap.char(10) )
      end                                                                                                           as InvoiceDocumentNumber,
      c.SupplierName,
      b.ProfitCenter,
      c.IndustryType,
      a.CompanyCodeCurrency,
      @Semantics.amount.currencyCode: 'TransactionCurrency'
      case
       when a.DebitCreditCode = 'H' and a.SpecialGLCode <> 'F'
            then b.CreditAmountInTransCrcy
       when a.DebitCreditCode = 'S' and a.SpecialGLCode <> 'F'
          then b.DebitAmountInTransCrcy
       else a.AmountInTransactionCurrency
      end                                                                                                           as InvoiceValue,

      @Semantics.amount.currencyCode: 'TransactionCurrency'
      a.TaxAmountInCoCodeCrcy,
      @Semantics.amount.currencyCode: 'TransactionCurrency'
      a.TaxBaseAmountInCoCodeCrcy,
      @Semantics.amount.currencyCode: 'TransactionCurrency'
      a.AmountInTransactionCurrency,
      a.AssignmentReference,
      a.TransactionCurrency,
      po.PurchasingHistoryDocumentItem,
      po.DocumentDate                                                                                               as PoDocumentDate,
      po.PostingDate                                                                                                as PoPostingDate,
      po.Material,
      prodtext.ProductName,
      case
      when po.Material = ''
           then 'SER'
      else PROD.ProductType
      end                                                                                                           as MaterialType,

      @Semantics.quantity.unitOfMeasure: 'BaseUnit'
      case
      when po.PurchasingHistoryCategory = 'Q' then po.Quantity  else cast( 0 as abap.quan(13,3) ) end               as ActualBilledQuantity,
  
      case
      when po.PurchasingHistoryCategory = 'Q' then po.Currency else cast( '' as abap.char(10) ) end                 as Currency,
      case
      when po.PurchasingHistoryCategory = 'Q' then po.PurchaseOrder else cast( '' as abap.char(10) ) end            as PurchaseOrder,
      @Semantics.amount.currencyCode: 'TransactionCurrency'
      case
      when po.PurchasingHistoryCategory = 'Q' then po.InvoiceAmtInCoCodeCrcy  else cast( 0 as abap.curr(13,2) ) end as InvoiceAmtInCoCodeCrcy,

      case
              when po_grn.PurchasingHistoryCategory = 'E' and (po_grn.GoodsMovementType = '101' or po_grn.GoodsMovementType = '105')
                  then po_grn.PurchasingHistoryDocument
                   else  cast( '' as abap.char(10) )
          end                                                                                                       as GRNNumber,
      case
             when po_grn.PurchasingHistoryCategory = 'E' and (po_grn.GoodsMovementType = '101' or po_grn.GoodsMovementType = '105')
                 then po_grn.Batch
                  else  cast( '' as abap.char(10) )
         end                                                                                                        as Batch,

      @Semantics.quantity.unitOfMeasure: 'BaseUnit'
      case
          when po_grn.PurchasingHistoryCategory = 'E' and (po_grn.GoodsMovementType = '101' or po_grn.GoodsMovementType = '105')
              then po_grn.Quantity
          else cast( 0 as abap.quan(13,3) )
      end                                                                                                           as GRNQuantity,
      po.PurchaseOrderQuantityUnit                                                                                  as BaseUnit,

      @Semantics.quantity.unitOfMeasure: 'BaseUnit'
      case
          when po_grn.Batch is not null and po_grn.Batch <> ''
          then cons.ConsumptionQty
           else cast( 0 as abap.quan(13,3) )
      end                                                                                                           as ConsumptionQty,
   @Semantics.quantity.unitOfMeasure: 'BaseUnit'
cast( po_grn.Quantity as abap.dec(13,3) )
- case
    when po_grn.Batch is not null and po_grn.Batch <> ''
    then coalesce( cast( cons.ConsumptionQty as abap.dec(13,3) ), cast( 0 as abap.dec(13,3) ) )
    else cast( 0 as abap.dec(13,3) )
  end                                                                                                           as BalancedQty,

      concat(
        cast(
            case
                when po_grn.Quantity is not null and po_grn.Quantity <> 0
                then
                    ( cast( cons.ConsumptionQty as abap.dec(13,3) )
                    / cast( po_grn.Quantity as abap.dec(13,3) ) ) * 100
                else 0
            end
        as abap.char(10)),
        '%'
      )                                                                                                             as ConsumptionPercent,

      _payment.PaidAmount                                                                                           as AmountAlreadyPaid,
      case
       when _payment.AmountToBePaid > 0 then - _payment.AmountToBePaid
       when _payment.AmountToBePaid < 0 then abs( _payment.AmountToBePaid )
         else
        cast(
            case
                when a.DebitCreditCode = 'H' and a.SpecialGLCode <> 'F'
                    then b.CreditAmountInTransCrcy
                when a.DebitCreditCode = 'S' and a.SpecialGLCode <> 'F'
                    then b.DebitAmountInTransCrcy
                else a.AmountInTransactionCurrency
            end
        as abap.dec(23,2) )
      end                                                                                                           as BalanceToBePaid,

      cast(
        case
            when po.Quantity is not null and po.Quantity <> 0
            then
                cast( po.PurOrdAmountInCompanyCodeCrcy as abap.decfloat34 )
                / cast( po.Quantity as abap.decfloat34 )
            else 0
        end
      as abap.dec(23,2) )                                                                                           as Price


}
where
           a.FinancialAccountType   =  'K'
  and      a.ClearingJournalEntry   is initial
  and      a.SpecialGLCode          <> 'H'
  and ( a.SpecialGLCode = 'F'
        or ( b.IsReversed is initial and b.IsReversal is initial ) )
  and(
           (
             a.AccountingDocumentType      <> 'KR'
             and  a.AccountingDocumentType <> 'RE'
             and  a.AccountingDocumentType <> 'KA'
             and  a.AccountingDocumentType <> 'UE'
           )
    or(
           a.AccountingDocumentType =  'KR'
         or a.AccountingDocumentType =  'RE'
         or a.AccountingDocumentType =  'KA'
         or a.AccountingDocumentType =  'UE'
      )
  )
  and(
           (
                 c.IndustryType <> 'MSME'
             and(
                  a.NetDueDate                                            is initial
               or a.NetDueDate                                            <= $session.system_date
               or dats_days_between( $session.system_date, a.NetDueDate ) <= 5
             )
           )

        or (
             c.IndustryType = 'MSME'
         and(
              dats_days_between( a.DueCalculationBaseDate, a.NetDueDate ) = 0

           or (
                dats_days_between( a.DueCalculationBaseDate, a.NetDueDate )         >= 45
            and dats_days_between( a.DueCalculationBaseDate, $session.system_date ) >= 40
              )

           or (
                dats_days_between( a.DueCalculationBaseDate, a.NetDueDate ) > 0
            and dats_days_between( a.DueCalculationBaseDate, a.NetDueDate ) < 45
            and dats_days_between( a.DueCalculationBaseDate, $session.system_date )
                  >= dats_days_between( a.DueCalculationBaseDate, a.NetDueDate ) - 5
              )
            )
           )
  );

