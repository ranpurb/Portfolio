/* ----------------------------------------------------------------------------------
This is sample query that I create to find differentiation between usage quantity and balance listed in inventory. 
To find where to fix
this query for sql-server
 ----------------------------------------------------------------------------------*/

with RowsToAdjust AS (
	SELECT ilf.item, ilf.location, ilf.costdate, ilf.quantity, ilf_sumquantity, 
	CASE WHEN ilf.conditioncode IS NULL THEN 'null' 
		ELSE ilf.conditioncode END AS conditioncode, 
	SUM(ilf.quantity) OVER (PARTITION BY ilf.item, ilf.location 
		ORDER BY ilf.costdate DESC) running_total,
	Inventory_curbal Inventory_curbal, 
	InvBal_condition, Total_Line, ilf.invlifofifoID line_id, ilf_concode
	FROM invlifofifo ilf
	left outer JOIN  (
		select COALESCE(ilf.item, ibal.item) AS item,i.rotating,i.status, 
		COALESCE(ilf.location, ibal.location) AS location, ibal.Inventory_curbal Inventory_curbal, 
		ibal.Inventory_curbal InvBal_condition,
		null physical_count,ilf.invlifofifo_qty ilf_sumquantity,Total_Line, 
		ibal.invbal_conditioncode ilf_concode
		FROM ( SELECT  ilfdata.item, ilfdata.location, 
				CASE WHEN ilfdata.conditioncode IS NULL THEN 'null' 
					ELSE ilfdata.conditioncode END AS ilf_conditioncode,
				SUM(ilfdata.quantity) AS invlifofifo_qty, count(invlifofifoID) Total_Line
			FROM invlifofifo ilfdata
			GROUP BY ilfdata.item, ilfdata.location, ilfdata.conditioncode
		) ilf
		FULL OUTER JOIN (
			SELECT ibal.item, ibal.location, 
				CASE WHEN ibal.conditioncode IS NULL THEN 'null' 
					ELSE ibal.conditioncode END AS invbal_conditioncode,
				SUM(ibal.curbal) AS Inventory_curbal
			FROM invbalances ibal 
			GROUP BY ibal.item, ibal.location, ibal.conditioncode
		) ibal ON ilf.item = ibal.item AND ilf.location = ibal.location
		   AND ilf.ilf_conditioncode = ibal.invbal_conditioncode
		left join item i on i.item=COALESCE(ilf.item, ibal.item)
		where i.rotating =0 and i.status != 'OBSOLETE'  and itemtype='ITEM'
		and (invlifofifo_qty>0 or ibal.Inventory_curbal>0) 
		and invlifofifo_qty>ibal.Inventory_curbal 
	) cd ON ilf.item = cd.item AND ilf.location = cd.location 
	and ilf_concode= CASE WHEN ilf.conditioncode IS NULL THEN 'null'  ELSE ilf.conditioncode END
	where cd.item is not null
), 
ActionableRows AS (
    SELECT RowsToAdjust.item,case when i.rotating=1 then 'Rotating' else 'Non-Rotating' end Rotating_Item, 
    i.itemtype item_type, ilf_sumquantity, Total_Line, line_id, 
    conditioncode, location, costdate, quantity lifofifo_quantity, running_total running_totalQty, 
    InvBal_condition, Inventory_curbal,
    CASE WHEN (running_total <= Inventory_curbal and Total_Line>1)THEN 'KEEP'
    	WHEN ((running_total - quantity < Inventory_curbal and running_total>Inventory_curbal) 
    		or (Total_Line=1 and running_total < Inventory_curbal))
    		THEN 'MODIFY' ELSE 'DELETE' END AS action,
    CASE WHEN CAST(running_total AS DECIMAL(15, 4)) - CAST(quantity AS DECIMAL(15, 4)) < CAST(Inventory_curbal AS DECIMAL(15, 4)) 
    	THEN CAST(Inventory_curbal AS DECIMAL(15, 4)) - (CAST(running_total AS DECIMAL(15, 4)) -CAST( quantity AS DECIMAL(15, 4)))
        ELSE 0 END AS new_quantity
    FROM RowsToAdjust
    	left join item i on i.item=RowsToAdjust.item
)
SELECT * 
FROM ActionableRows 
WHERE  Rotating_Item='Non-Rotating' and item_type='ITEM'
order by item desc, location
;
