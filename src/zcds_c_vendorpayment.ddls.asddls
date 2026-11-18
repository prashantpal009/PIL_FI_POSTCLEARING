    @AbapCatalog.viewEnhancementCategory: [#NONE]
    @EndUserText.label: 'Projection View for Vendor Payment'
    @AccessControl.authorizationCheck: #NOT_REQUIRED
    @Metadata.allowExtensions: true
    @UI.headerInfo: {
        typeName: 'Vendor Payment',
        typeNamePlural: 'Vendor Payments',
        title: { type: #STANDARD, value: 'Supplier' },
        description: { type: #STANDARD, value: 'CompanyCode' }
    }
    
    define root view entity ZCDS_C_VendorPayment
      //provider contract transactional_query
      as projection on ZCDS_Vendor_PaymentRAP
    {
          @UI.lineItem:       [{ position: 1, label: 'Key Value' }]
      key Db_Key,
    
          @UI.lineItem:       [{ position: 5 }]
          @EndUserText.label: 'Identification Number'
          @UI.selectionField: [{ position: 5 }]
          @Consumption.valueHelpDefinition: [{entity: { name: 'ZVH_APPROVAL2', element: 'id_no' }   }]
          IdNo,
    
          @UI.lineItem:       [{ position: 10, label: 'Company Code' }]
          CompanyCode,
    
          @UI.lineItem:       [{ position: 20 }]
          @EndUserText.label: 'Supplier'
    //      @UI.selectionField: [{ position: 30 }]
          Supplier,
    
          @UI.lineItem:       [{ position: 30, label: 'Supplier Name' }]
          SupplierName,
    
          @UI.lineItem:       [{ position: 35, label: 'Industry Type' }]
          IndustryType,
    
          @UI.lineItem:       [{ position: 40, label: 'Invoice Date' }]
          InvoiceDate,
    
          @UI.lineItem:       [{ position: 41, label: 'Posting Date' }]
          PostingDate,
    
          @UI.lineItem:       [{ position: 42, label: 'Payment Days' }]
          PaymentDays,
    
          @UI.lineItem:       [{ position: 43, label: 'Invoice Number' }]
          InvoiceNo,
    
          @UI.lineItem:       [{ position: 44, label: 'Transaction Currency' }]
          TransactionCurrency,
    
          @UI.lineItem:       [{ position: 45, label: 'Special GL Code' }]
          SpecialGLCode,
    
          @UI.lineItem:       [{ position: 50, label: 'Invoice Value' }]
          InvoiceValue,
    
          @UI.lineItem:       [{ position: 51, label: 'Amount Already Paid' }]
          AmountAlreadyPaid,
    
          @UI.lineItem:       [{ position: 52, label: 'Balance To Be Paid' }]
          BalanceToBePaid,
    
          @UI.lineItem:       [{ position: 60, label: 'Proposed Amount' }]
          AmountProposal,
    
          @UI.lineItem:       [{ position: 61 }]
          @EndUserText.label: 'Accounting Document'
          JournalEntry,
    
          @EndUserText.label: 'Invoice Reference'
          @UI.lineItem: [{ position: 62 }]
          InvoiceReference,
          
          @EndUserText.label: 'Invoice Reference Fiscle Year'
          @UI.lineItem: [{ position: 62.1 }]
          InvoiceReferenceFiscalYear,
          
          
            @EndUserText.label: 'Assignment Reference'
          @UI.lineItem: [{ position: 62.2 }]
          AssignmentReference ,
    
          @UI.lineItem:       [{ position: 63, label: 'Original Reference Document' }]
          OriginalReferenceDocument,
    
          @UI.lineItem:       [{ position: 64, label: 'Accounting Document Type' }]
          JournalEntryType,
    
          @UI.lineItem:       [{ position: 65, label: 'Fiscal Year' }]
          FiscalYear,
    
          @UI.lineItem:       [{ position: 66, label: 'Fiscal Period' }]
          FiscalPeriod,
    
          @UI.lineItem:       [{ position: 67, label: 'House Bank' }]
          HouseBank,
    
          @UI.lineItem:       [{ position: 68, label: 'House Bank Account' }]
          HouseBankAccount,
    
          @UI.lineItem:       [{ position: 69, label: 'G/L Account' }]
          GlAccount,
    
          @UI.lineItem:       [{ position: 70, label: 'Bank Profit Center' }]
          BankProfitCenter,
    
          @UI.lineItem:       [{ position: 71, label: 'Profit Center' }]
          ProfitCenter,
    
          @UI.lineItem:       [{ position: 72, label: 'Rate' }]
          Rate,
    
          @UI.lineItem:       [{ position: 73, label: 'Purchase Order' }]
          PurchaseOrder,
    
          @UI.lineItem:       [{ position: 74, label: 'PO Qty Unit' }]
          PoQtyUnit,
            
            @UI.lineItem:       [{ position: 75, label: 'PO Qty' }]
          PoQty,
    
          @UI.lineItem:       [{ position: 80, label: 'PO History Document Item' }]
          PoHistoryDocItem,
    
          @UI.lineItem:       [{ position: 90, label: 'PO Document Date' }]
          PoDocumentDate,
    
          @UI.lineItem:       [{ position: 100, label: 'PO Posting Date' }]
          PoPostingDate,
    
          @UI.lineItem:       [{ position: 110, label: 'Invoice Document Number' }]
          InvoiceDocNumber,
    
          @UI.lineItem:       [{ position: 120, label: 'Currency' }]
          Currency,
    
          @UI.lineItem:       [{ position: 130, label: 'PO Invoice Value' }]
          InvoiceValuePo,
    
          @UI.lineItem:       [{ position: 140, label: 'Net Price Amount' }]
          NetPriceAmount,
    
          @UI.lineItem:       [{ position: 150, label: 'Actual Billed Qty' }]
          ActualBilledQty,
    
          @UI.lineItem:       [{ position: 160, label: 'GRN Number' }]
          GrnNumber,
    
          @UI.lineItem:       [{ position: 170, label: 'Batch' }]
          Batch,
    
          @UI.lineItem:       [{ position: 180, label: 'GRN Quantity' }]
          GrnQuantity,
    
          @UI.lineItem:       [{ position: 190, label: 'Consumption Quantity' }]
          ConsumptionQuantity,
          
          @UI.lineItem:       [{ position: 191, label: 'Price' }]
          Price,
    
          @UI.lineItem:       [{ position: 200, label: 'Balance Quantity' }]
          BalanceQuantity,
    
          @UI.lineItem:       [{ position: 210, label: 'Consumtion Percentage %' }]
          ConsumptionPercentage,
    
          @UI.lineItem:       [{ position: 220, label: 'Product' }]
          Material,
          
          @UI.lineItem:       [{ position: 221, label: 'Product Description' }]
          MaterialName,
    
          @UI.lineItem:       [{ position: 230, label: 'Material Type' }]
          MaterialType,
    
          @UI.lineItem:       [{ position: 231, label: 'Proposal Status' }]
          ProposalStatus,
    
          @UI.lineItem:       [{ position: 240, label: 'Approval Status 1' }]
          Approval1Status,
          @UI.lineItem:       [{ position: 241, label: 'Approved By 1' }]
          Approval1User,
          @UI.lineItem:       [{ position: 242, label: 'Approved On1' }]
          Approval1On,
          @UI.lineItem:       [{ position: 243, label: 'Approval Time 1' }]
          Approval1Time,
    
          @UI.lineItem:       [{ position: 250, label: 'Approval Status 2' }]
          Approval2Status,
          @UI.lineItem:       [{ position: 251, label: 'Approved By 2' }]
          Approval2User,
          @UI.lineItem:       [{ position: 252, label: 'Approved On 2' }]
          Approval2On,
          @UI.lineItem:       [{ position: 253, label: 'Approval Time 2' }]
          Approval2Time,
    
          @UI.lineItem:       [{ position: 254, label: 'Approval Status 3' }]
          Approval3Status,
          @UI.lineItem:       [{ position: 255, label: 'Approved By 3' }]
          Approval3User,
          @UI.lineItem:       [{ position: 256, label: 'Approved On 3' }]
          Approval3On,
          @UI.lineItem:       [{ position: 257, label: 'Approval Time 3' }]
          Approval3Time,
    
          @UI.lineItem:       [{ position: 258, label: 'Bank Transacton Id' }]
          TransactionId,
          @UI.lineItem:       [{ position: 259, label: 'Payment Status' }]
          PaymentStatus,
          @UI.lineItem:       [{ position: 260, label: 'UTR Number' }]
          UTRNumber,
    
          @UI.lineItem:       [{ position: 261, label: 'Posting Document' }]
          PostingDocument,
    
          @UI.lineItem:       [{ position: 262, label: 'Post Status' }]
          PostStatus,
          
          @UI.lineItem:       [{ position: 263, label: 'Post Error' }]
          PostingError,
     
     
          @UI.lineItem:       [{ position: 270, label: 'Clearing Accounting Document' }]
          ClearingAcctgDocument,
    
          @UI.lineItem:       [{ position: 280, label: 'Clearing Document Year' }]
          ClearingDocYear,
         
          @UI.lineItem:       [{ position: 263, label: 'Clearing Error' }]
          ClearingError,
  
          @UI.hidden: true
          CreatedBy,
          @UI.hidden: true
          CreatedAt,
          @UI.hidden: true
          LastChangedBy,
          @UI.hidden: true
          LastChangedAt,
          @UI.hidden: true
          LocalLastChangedAt
    }
