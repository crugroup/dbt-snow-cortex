SELECT
  'sample_id_1' AS id,
  'Copper ore mined from open pit, grade 2.5%' AS description,
  'Copper' AS commodity_name,
  CURRENT_DATE() AS data_date
UNION ALL
SELECT
  'sample_id_2' AS id,
  'Iron ore pellets, 65% Fe, delivered CIF' AS description,
  'Iron Ore' AS commodity_name,
  CURRENT_DATE() AS data_date
UNION ALL
SELECT
  'sample_id_3' AS id,
  'Metallurgical coal, premium low-vol, FOB Australia' AS description,
  'Metallurgical coal' AS commodity_name,
  CURRENT_DATE() AS data_date
