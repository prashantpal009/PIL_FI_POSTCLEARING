define view entity ZCDS_ConsumptionQty
  as select from I_MaterialDocumentItem_2
{
  key Plant,
  key Material,
  key Batch,

      @Semantics.quantity.unitOfMeasure: 'MaterialBaseUnit'
      cast( abs( sum( case DebitCreditCode
                        when 'H' then QuantityInBaseUnit * -1
                        when 'S' then QuantityInBaseUnit
                        else 0
                      end ) ) as abap.quan(23,3) )  as ConsumptionQty,

      MaterialBaseUnit
}
where
       Batch <> ''
  and(
       GoodsMovementType = '201' or GoodsMovementType = '202'
    or GoodsMovementType = '221' or GoodsMovementType = '222'
    or GoodsMovementType = '231' or GoodsMovementType = '232'
    or GoodsMovementType = '241' or GoodsMovementType = '242'
    or GoodsMovementType = '261' or GoodsMovementType = '262'
    or GoodsMovementType = '281' or GoodsMovementType = '282'
    or GoodsMovementType = '291' or GoodsMovementType = '292'
    or GoodsMovementType = '301' or GoodsMovementType = '302'
    or GoodsMovementType = '303' or GoodsMovementType = '304'
    or GoodsMovementType = '351' or GoodsMovementType = '352'
    or GoodsMovementType = '641' or GoodsMovementType = '642'
    or GoodsMovementType = '643' or GoodsMovementType = '644'
    or GoodsMovementType = '645' or GoodsMovementType = '646'
    or GoodsMovementType = '647' or GoodsMovementType = '648'
    or GoodsMovementType = '541' or GoodsMovementType = '542'
    or GoodsMovementType = '543' or GoodsMovementType = '544'
    or GoodsMovementType = '551' or GoodsMovementType = '552'
    or GoodsMovementType = '553' or GoodsMovementType = '554'
    or GoodsMovementType = '555' or GoodsMovementType = '556'
    or GoodsMovementType = '331' or GoodsMovementType = '332'
    or GoodsMovementType = '333' or GoodsMovementType = '334'
    or GoodsMovementType = '335' or GoodsMovementType = '336'
    or GoodsMovementType = '601' or GoodsMovementType = '602'
  )
group by
  Plant,
  Material,
  Batch,
  MaterialBaseUnit
