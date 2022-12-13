----OPP MERCHANT ARI
set forecast_date = DATE('2023-01-01')-365; 

WITH FY22_Run_Rate_Merchants AS(
SELECT 
ACCOUNT_NAME, 
OPPORTUNITY_NAME, 
OPPORTUNITY_STAGENAME as Opp_Stage, 
CONCAT(FISCAL_YEAR_CLOSE_DATE,'-Q',FISCAL_QUARTER_CLOSE_DATE) as FQ_Close, 
OPPORTUNITY_CLOSE_DT,
OPPORTUNITY_CREATED_DT_UTC,
OPPORTUNITY_EST_GMV_FY23, 
MERCHANT_FORECASTED_EST_GMV_FY23,
OPPORTUNITY_FORECASTED_PROBABILLITY,
OPPORTUNITY_EST_GMV_FY23*OPPORTUNITY_FORECASTED_PROBABILLITY as FY23_Forecasted_Est_GMV,
OPPORTUNITY_MERCHANT_ARI, 
OPPORTUNITY_LAUNCH_DT as Launch_Date, 
OPPORTUNITY_FIRST_CAPTURE_DATE as Capture_Date,
CASE WHEN OPPORTUNITY_OWNER_SEGMENT = 'N/A' THEN 'New Markets'
     ELSE OPPORTUNITY_OWNER_SEGMENT END AS Rep_Segment,
ACCOUNT_SEGMENT,
ACCOUNT_SALES_REPORTING_SEGMENT,
OPPORTUNITY_OWNER_ROLE,
ACCOUNT_VERTICAL, 
ACCOUNT_INDUSTRY, 
ACCOUNT_SUB_INDUSTRY
FROM PROD__US.DBT_ANALYTICS.SALES_TERRITORY_DEAL_MART td
WHERE IS_SALES_OPPORTUNITY = TRUE 
AND Opp_Stage = 'Closed Won (Signed)' 
AND FQ_Close IN ('2022-Q1','2022-Q2','2022-Q3','2022-Q4')
AND OPPORTUNITY_CREATED_DT_UTC >= $forecast_date
AND CAPTURE_DATE IS NOT NULL
AND CAPTURE_DATE >= $forecast_date
),

Run_Rate_Actuals AS(
select
    actuals_as_of_date
    ,dd.week_start_date
    ,dd.week_start_date + 6 as week_end_date
    ,merchant_name
    ,merchant_ari
    ,product_type
    ,vertical
    ,CAPTURE_DATE
    , sum(gmv_net_refunds) as gmv_net
    , sum(contribution_margin) as cm
    , sum(budget_gmv_net_refunds) as budget_gmv_net
    , sum(budget_contribution_margin) as budget_cm
    , sum(in_month_fc_gmv_net_refunds) as sept_fc_gmv_net
    , sum(in_month_fc_contribution_margin) as sept_fc_budget_cm
    , concat(merchant_ari,'-',week_start_date,'-',product_type,'-',vertical) as actuals_key
from prod__workspace__us.scratch_t_strategicfinance.vol_trends_daily sfc
left join PROD__US.DBT_ANALYTICS.DATE_DIM dd on date(sfc.effective_date) = dd.date_key
left join FY22_Run_Rate_Merchants on sfc.MERCHANT_ARI = FY22_Run_Rate_Merchants.OPPORTUNITY_MERCHANT_ARI 
where 1=1
    and sfc.effective_date between $forecast_date and '2022-06-30' 
    and MERCHANT_ARI in (SELECT OPPORTUNITY_MERCHANT_ARI FROM FY22_Run_Rate_Merchants) 
    and gmv_net_refunds is not null
GROUP BY 1,2,3,4,5,6,7,8
ORDER BY 2 desc
)

SELECT SUM(GMV_NET)
FROM Run_Rate_Actuals 
WHERE WEEK_START_DATE >= CAPTURE_DATE 
ORDER BY GMV_NET
