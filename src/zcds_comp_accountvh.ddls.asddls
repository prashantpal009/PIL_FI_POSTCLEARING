@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Value help for Companycode and AccountID'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZCDS_Comp_AccountVH as select distinct from I_HouseBankAccountText as a
left outer join I_HouseBankAccountLinkage as b on a.HouseBank = b.HouseBank and a.HouseBankAccount = b.HouseBankAccount
//left outer join i_bankaccount as c on b.BankAccount = c.BankAccountNumber
{
    key a.Language,
    key a.CompanyCode,
    key a._CompanyCode.CompanyCodeName,
    key a.HouseBank,
    key a.HouseBankAccount,
    b.GLAccount,
    b.BankAccountCurrency,
    a.HouseBankAccountDescription,
    
    /* Associations */
    a._CompanyCode,
    a._HouseBank,
    a._Language
}where b.BankAccountCurrency = 'INR' 
  and (   a.HouseBank = 'HDFC1'
       or a.HouseBank = 'HDFC2'
       or a.HouseBank = 'HDFC5'
       or a.HouseBank = 'HDFC7'
       or a.HouseBank = 'YESB1' )

