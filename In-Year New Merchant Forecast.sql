--This query is used to forecast in-year impact of new merchants

------------------------------------------------
--Assumptions are captured in first section here
------------------------------------------------

--Forecast Start Date. Adjust as needed to project from a given date. Default is forecast based on current date
set forecast_date = current_date();

--Temp table with ramp assumptions. Captures expected volume % of first 12 month volume by month 
CREATE temporary table Ramp_Assumptions (
Segment varchar(12),
Months int,
Volume_percent float);

INSERT INTO Ramp_Assumptions VALUES 
('Key', 0, 0),
('Key', 1, 0.86),
('Key', 2, 6.05),
('Key', 3, 10.39),
('Key', 4, 15.42),
('Key', 5, 23.56),
('Key', 6, 35.74),
('Key', 7, 48.17),
('Key', 8, 63.21),
('Key', 9, 76.68),
('Key', 10, 83.60),
('Key', 11, 91.58),
('Key', 12, 100),
('Enterprise', 0, 0),
('Enterprise', 1, 2.04),
('Enterprise', 2, 12.91),
('Enterprise', 3, 27.56),
('Enterprise', 4, 43.33),
('Enterprise', 5, 48.93),
('Enterprise', 6, 54.74),
('Enterprise', 7, 60.12),
('Enterprise', 8, 66.97),
('Enterprise', 9, 76.76),
('Enterprise', 10, 84.32),
('Enterprise', 11, 92.78),
('Enterprise', 12, 100),
('SMB', 0, 0),
('SMB', 1, 2.66),
('SMB', 2, 8.39),
('SMB', 3, 15.75),
('SMB', 4, 22.47),
('SMB', 5, 29.98),
('SMB', 6, 38.02),
('SMB', 7, 46.60),
('SMB', 8, 55.85),
('SMB', 9, 65.42),
('SMB', 10, 75.41),
('SMB', 11, 87.29),
('SMB', 12, 100),
('New Markets', 0, 0),
('New Markets', 1, 9.78),
('New Markets', 2, 16.32),
('New Markets', 3, 24.20),
('New Markets', 4, 32.59),
('New Markets', 5, 40.39),
('New Markets', 6, 47.18),
('New Markets', 7, 53.90),
('New Markets', 8, 61.53),
('New Markets', 9, 70.06),
('New Markets', 10, 79.82),
('New Markets', 11, 91.04),
('New Markets', 12, 100);

---------------------------------------------------------------------------------------------------
--Second section builds uses a CTE and assumptions to calculate expected in-year merchant contribution 
---------------------------------------------------------------------------------------------------

--CTE to capture opps already in the finance forecast that should be excluded from in-year forecast
WITH Opps_in_forecast AS (
SELECT MERCHANT_ARI
FROM PROD__WORKSPACE__US.SCRATCH_T_STRATEGICFINANCE.VOL_TRENDS_DAILY
WHERE LAUNCH_DATE >= '2022-07-01' AND (EFFECTIVE_DATE BETWEEN '2022-07-01' AND '2023-06-30') AND IN_MONTH_FC_GMV_NET_REFUNDS IS NOT NULL
GROUP BY 1
ORDER BY 1 asc),

Ramp AS (
SELECT CONCAT(Segment,Months) as Ramp_Key, VOLUME_PERCENT FROM Ramp_Assumptions),

--Sales Pipeline Captured in FY23, Signed but not launched, and In FY23 pipeline not signed
Pipeline AS (
SELECT 
ACCOUNT_NAME, 
OPPORTUNITY_NAME, 
OPPORTUNITY_STAGENAME as Opp_Stage, 
CONCAT(FISCAL_YEAR_CLOSE_DATE,'-Q',FISCAL_QUARTER_CLOSE_DATE) as FQ_Close, 
OPPORTUNITY_CLOSE_DT,
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
ACCOUNT_SUB_INDUSTRY,
CASE  WHEN Opp_Stage = 'Closed Won (Signed)' AND Capture_Date >= '2022-07-01' THEN 'Launched' --Captured in FY23
      WHEN Opp_Stage = 'Closed Won (Signed)' AND Capture_Date IS NULL THEN 'Signed but not launched' --Signed but not launched
      WHEN Opp_Stage != 'Closed Won (Signed)' AND Opp_Stage != 'Closed Lost' AND FISCAL_YEAR_CLOSE_DATE IN (2023) THEN 'In FY23 Pipeline, not signed'
      ELSE 'Remove' END as GMV_FORECAST_BUCKET,
CASE WHEN OPPORTUNITY_OWNER_ROLE = 'Channel Sales' THEN 1 
     WHEN OPPORTUNITY_OWNER_ROLE = 'Strategic Partnerships' THEN 1
     ELSE 0 END as Strategic_Partnerships_Flag,
---Launch probability assumption
CASE WHEN ACCOUNT_SALES_REPORTING_SEGMENT = 'Key' THEN 0.8
     WHEN ACCOUNT_SALES_REPORTING_SEGMENT = 'Enterprise' THEN 0.8
     WHEN ACCOUNT_SALES_REPORTING_SEGMENT = 'SMB' THEN 0.45
     WHEN ACCOUNT_SALES_REPORTING_SEGMENT = 'New Markets' THEN 0.63
     ELSE 0 END as Launch_Probability_Assumption,
--Days to launch assumption
CASE WHEN ACCOUNT_SALES_REPORTING_SEGMENT = 'Key' THEN 180
     WHEN ACCOUNT_SALES_REPORTING_SEGMENT = 'Enterprise' THEN 150
     WHEN ACCOUNT_SALES_REPORTING_SEGMENT = 'SMB' THEN 50
     WHEN ACCOUNT_SALES_REPORTING_SEGMENT = 'New Markets' THEN 70
     ELSE 0 END as Days_to_Launch_Assumption,
--Days to capture assumption
CASE WHEN ACCOUNT_SALES_REPORTING_SEGMENT = 'Key' THEN 10
     WHEN ACCOUNT_SALES_REPORTING_SEGMENT = 'Enterprise' THEN 10
     WHEN ACCOUNT_SALES_REPORTING_SEGMENT = 'SMB' THEN 15
     WHEN ACCOUNT_SALES_REPORTING_SEGMENT = 'New Markets' THEN 10
     ELSE 0 END as Days_to_Capture_Assumption,
CASE WHEN OPPORTUNITY_MERCHANT_ARI IN (SELECT * FROM Opps_in_forecast) THEN 1
     ELSE 0 END as Remove_flag_already_counted,
CASE WHEN Capture_Date IS NOT NULL THEN DATE(Capture_Date)
     WHEN DATE(OPPORTUNITY_CLOSE_DT) < $forecast_date THEN $forecast_date + Days_to_Launch_Assumption + Days_to_Capture_Assumption
     ELSE DATE(OPPORTUNITY_CLOSE_DT) + Days_to_Launch_Assumption + Days_to_Capture_Assumption END as Projected_Capture_Date,
CASE WHEN Projected_Capture_Date >= DATE('2023-06-30') THEN 0
     ELSE DATE('2023-06-30') - Projected_Capture_Date END as FY23_Capture_Days,
CASE WHEN Remove_flag_already_counted = 1 THEN 0
     ELSE ROUND(FY23_Capture_Days/30) END AS FY23_Capture_Months,
CONCAT(ACCOUNT_SALES_REPORTING_SEGMENT, FY23_Capture_Months) as Ramp_Key,
CASE WHEN GMV_FORECAST_BUCKET = 'Signed but not launched' AND $forecast_date - OPPORTUNITY_CLOSE_DT > 270 AND ACCOUNT_SALES_REPORTING_SEGMENT != 'Key' THEN 0.05
     WHEN GMV_FORECAST_BUCKET = 'Signed but not launched' AND $forecast_date - OPPORTUNITY_CLOSE_DT > 365 AND ACCOUNT_SALES_REPORTING_SEGMENT = 'Key' THEN 0.3
     ELSE 1 END AS Time_Adjustment_Factor --Factor to adjust for reduced probability of laucnh after a long timeframe has elapsed post signing
FROM PROD__US.DBT_ANALYTICS.SALES_TERRITORY_DEAL_MART td
WHERE GMV_FORECAST_BUCKET NOT IN ('Remove') AND IS_SALES_OPPORTUNITY = TRUE AND Opp_Stage != 'Pre Opportunity' AND FQ_Close IN ('2022-Q1','2022-Q2','2022-Q3','2022-Q4','2023-Q1','2023-Q2','2023-Q3','2023-Q4')
),

FINAL_TABLE AS (
SELECT *, 
CASE WHEN OPPORTUNITY_NAME = 'Microsoft Corporation: 2021-09-07 - Microsoft Edge Browser' THEN 604000
ELSE (VOLUME_PERCENT/100)*(FY23_FORECASTED_EST_GMV*2)*LAUNCH_PROBABILITY_ASSUMPTION*Time_Adjustment_Factor END as Weighted_In_Year_Expected_Volume 
--Calculate expected in-year and provide additional manual adjustments. Here I'm adjusting for an outlier in the Est_GMV for Microsoft 
FROM PIPELINE
LEFT JOIN RAMP r ON pipeline.Ramp_Key = r.Ramp_Key)

SELECT ACCOUNT_SALES_REPORTING_SEGMENT, STRATEGIC_PARTNERSHIPS_FLAG, ROUND(SUM(WEIGHTED_IN_YEAR_EXPECTED_VOLUME))
FROM FINAL_TABLE
GROUP BY 1,2
ORDER BY 3 desc
