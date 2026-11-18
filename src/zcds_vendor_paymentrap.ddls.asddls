@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'CDS For Vendor Payment Records'
@Metadata.ignorePropagatedAnnotations: true
define root view entity ZCDS_Vendor_PaymentRAP
  as select from zvendor_payment
{
  key db_key                      as Db_Key,
      id_no                       as IdNo,
      company_code                as CompanyCode,
      journal_entry               as JournalEntry,
      invoice_reference           as InvoiceReference,
      invoice_referencefiscleyear as InvoiceReferenceFiscalYear,
      originalreference_document  as OriginalReferenceDocument,
      journal_entry_type          as JournalEntryType,
      supplier                    as Supplier,
      supplier_name               as SupplierName,
      fiscal_year                 as FiscalYear,
      fiscal_period               as FiscalPeriod,
      speciaglcode                as SpecialGLCode,
      industry_type               as IndustryType,
      invoice_date                as InvoiceDate,
      posting_date                as PostingDate,
      payment_days                as PaymentDays,
      invoice_no                  as InvoiceNo,
      assignmentreference         as AssignmentReference,
      transaction_currency        as TransactionCurrency,
      currency                    as Currency,
      @Semantics.amount.currencyCode : 'TransactionCurrency'
      invoice_value               as InvoiceValue,
      house_bank                  as HouseBank,
      house_bank_account          as HouseBankAccount,
      gl_account                  as GlAccount,
      bank_profit_center          as BankProfitCenter,
      @Semantics.amount.currencyCode : 'TransactionCurrency'
      amount_already_paid         as AmountAlreadyPaid,
      @Semantics.amount.currencyCode : 'TransactionCurrency'
      balance_to_be_paid          as BalanceToBePaid,
      @Semantics.amount.currencyCode : 'TransactionCurrency'
      amount_proposal             as AmountProposal,
      rate                        as Rate,
      profit_center               as ProfitCenter,
      invoice_doc_number          as InvoiceDocNumber,
      po_history_doc_item         as PoHistoryDocItem,
      po_document_date            as PoDocumentDate,
      po_posting_date             as PoPostingDate,
      material                    as Material,
      materialname                as MaterialName,
      material_type               as MaterialType,
      po_qty_unit                 as PoQtyUnit,
      @Semantics.quantity.unitOfMeasure : 'PoQtyUnit'
      po_qty                      as PoQty,
      @Semantics.amount.currencyCode : 'TransactionCurrency'
      invoice_value_po            as InvoiceValuePo,
      net_price_amount            as NetPriceAmount,
      purchase_order              as PurchaseOrder,
      @Semantics.quantity.unitOfMeasure : 'PoQtyUnit'
      actual_billed_qty           as ActualBilledQty,
      grn_number                  as GrnNumber,
      batch                       as Batch,
      @Semantics.quantity.unitOfMeasure : 'PoQtyUnit'
      grn_quantity                as GrnQuantity,
      @Semantics.quantity.unitOfMeasure : 'PoQtyUnit'
      consumption_quantity        as ConsumptionQuantity,
      @Semantics.quantity.unitOfMeasure : 'PoQtyUnit'
      balance_quantity            as BalanceQuantity,
      consumption_percentage      as ConsumptionPercentage,
      price                       as Price,
      proposal_status             as ProposalStatus,
      approval1_status            as Approval1Status,
      approval1_user              as Approval1User,
      approval1_on                as Approval1On,
      approval1_time              as Approval1Time,
      approval2_status            as Approval2Status,
      approval2_user              as Approval2User,
      approval2_on                as Approval2On,
      approval2_time              as Approval2Time,
      approval3_status            as Approval3Status,
      approval3_user              as Approval3User,
      approval3_on                as Approval3On,
      approval3_time              as Approval3Time,
      transactionid               as TransactionId,
      payment_status              as PaymentStatus,
      utrnumber                   as UTRNumber,
      postingdocument             as PostingDocument,
      post_status                 as PostStatus,
      postingerror                as PostingError,
      clearing_acctg_document     as ClearingAcctgDocument,
      clearing_doc_year           as ClearingDocYear,
      clearingerror               as ClearingError,
      @Semantics.user.createdBy:true
      created_by                  as CreatedBy,
      @Semantics.systemDateTime.createdAt:true
      created_at                  as CreatedAt,
      @Semantics.user.lastChangedBy:true
      last_changed_by             as LastChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at             as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at       as LocalLastChangedAt
}
