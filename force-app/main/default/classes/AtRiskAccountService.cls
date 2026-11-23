/**
 * Business logic: which accounts are at risk, and which should be called first?
 *
 * Data Cloud (Calculated Insight) provides the numbers per account, built from ERP orders
 * that are linked to CRM accounts through the shared account number.
 * This class applies the risk rule and ranks the result. The rule lives in
 * Apex on purpose: it is version-controlled, unit-tested and easy to explain.
 *
 * Risk rule (an account is "at risk" if ANY is true):
 *   1. No order for DAYS_QUIET_THRESHOLD days or more ("gone quiet")
 *   2. Revenue in the last 90 days fell by DROP_THRESHOLD or more vs the 90 days before ("declining")
 * Ranking: highest 12-month revenue first = most money at stake.
 */
public with sharing class AtRiskAccountService {

    public static final Integer DAYS_QUIET_THRESHOLD = 60;
    public static final Decimal DROP_THRESHOLD = 0.40;   // 40 % drop

    @TestVisible
    private static IDataCloudQuery queryClient = new DataCloudQueryService();

    public class AtRiskAccount {
        public Id accountId;
        public String accountName;
        public String ownerName;
        public Decimal revenue12m;
        public Decimal revenueLast90d;
        public Decimal revenuePrev90d;
        public Integer daysSinceLastOrder;
        public List<String> reasons = new List<String>();
    }

    /**
     * @param maxResults      how many accounts to return (default 5)
     * @param minRevenue12m   ignore small accounts below this 12-month revenue (default 0)
     * @param onlyMyAccounts  true = only accounts owned by the running user
     */
    public List<AtRiskAccount> getAtRiskAccounts(Integer maxResults, Decimal minRevenue12m, Boolean onlyMyAccounts) {
        Integer limitN = (maxResults == null || maxResults <= 0) ? 5 : Math.min(maxResults, 50);
        Decimal minRev = (minRevenue12m == null) ? 0.0 : minRevenue12m;

        // 1) Read insight rows from Data Cloud (one row per CRM account number)
        String sql =
            'SELECT ' + DataCloudNames.CI_ACCOUNT_NUMBER + ' AS account_number, ' +
            DataCloudNames.CI_REVENUE_12M + ' AS revenue_12m, ' +
            DataCloudNames.CI_REVENUE_LAST_90D + ' AS revenue_last_90d, ' +
            DataCloudNames.CI_REVENUE_PREV_90D + ' AS revenue_prev_90d, ' +
            DataCloudNames.CI_DAYS_SINCE_ORDER + ' AS days_since_last_order ' +
            'FROM ' + DataCloudNames.CI_OBJECT;

        List<Map<String, Object>> rows = queryClient.query(sql);

        // 2) Apply the risk rule
        Map<String, AtRiskAccount> byNumber = new Map<String, AtRiskAccount>();
        for (Map<String, Object> row : rows) {
            Object rawNumber = row.get('account_number');
            String accNumber = rawNumber == null ? null : String.valueOf(rawNumber).trim();
            if (String.isBlank(accNumber)) {
                continue;
            }
            AtRiskAccount a = new AtRiskAccount();
            a.revenue12m = toDecimal(row.get('revenue_12m'));
            a.revenueLast90d = toDecimal(row.get('revenue_last_90d'));
            a.revenuePrev90d = toDecimal(row.get('revenue_prev_90d'));
            Decimal days = toDecimal(row.get('days_since_last_order'));
            a.daysSinceLastOrder = days == null ? null : days.intValue();

            evaluate(a);
            if (!a.reasons.isEmpty() && a.revenue12m != null && a.revenue12m >= minRev) {
                byNumber.put(accNumber, a);
            }
        }
        if (byNumber.isEmpty()) {
            return new List<AtRiskAccount>();
        }

        // 3) Match to CRM accounts on AccountNumber (the shared key between CRM and ERP).
        //    Sharing rules apply: users only see accounts they have access to.
        Set<String> numbers = byNumber.keySet();
        Id me = UserInfo.getUserId();
        String soql = 'SELECT Id, Name, AccountNumber, Owner.Name FROM Account WHERE AccountNumber IN :numbers';
        if (onlyMyAccounts == true) {
            soql += ' AND OwnerId = :me';
        }
        List<AtRiskAccount> result = new List<AtRiskAccount>();
        for (Account acc : Database.query(soql)) {
            AtRiskAccount a = byNumber.get(acc.AccountNumber);
            if (a == null || a.accountId != null) {
                continue; // skip duplicates with the same account number
            }
            a.accountId = acc.Id;
            a.accountName = acc.Name;
            a.ownerName = acc.Owner?.Name;
            result.add(a);
        }

        // 4) Rank by money at stake, then cut to N
        result.sort(new ByRevenueDesc());
        List<AtRiskAccount> top = new List<AtRiskAccount>();
        for (Integer i = 0; i < Math.min(limitN, result.size()); i++) {
            top.add(result[i]);
        }
        return top;
    }

    @TestVisible
    private static void evaluate(AtRiskAccount a) {
        if (a.daysSinceLastOrder != null && a.daysSinceLastOrder >= DAYS_QUIET_THRESHOLD) {
            a.reasons.add('No order for ' + a.daysSinceLastOrder + ' days');
        }
        if (a.revenuePrev90d != null && a.revenuePrev90d > 0 && a.revenueLast90d != null) {
            Decimal change = (a.revenueLast90d - a.revenuePrev90d) / a.revenuePrev90d;
            if (change <= -DROP_THRESHOLD) {
                a.reasons.add('Revenue down ' + Math.abs((change * 100).setScale(0)) + '% vs previous 90 days');
            }
        }
    }

    /** Plain-text answer for the agent to read back to the user. */
    public static String toSummary(List<AtRiskAccount> accounts) {
        if (accounts == null || accounts.isEmpty()) {
            return 'No at-risk accounts found with the current rules (no order for ' + DAYS_QUIET_THRESHOLD +
                   '+ days, or revenue down ' + (DROP_THRESHOLD * 100).intValue() + '%+ vs the previous 90 days).';
        }
        List<String> lines = new List<String>();
        lines.add('Call these ' + accounts.size() + ' accounts this week, ranked by 12-month revenue at stake:');
        Integer i = 1;
        for (AtRiskAccount a : accounts) {
            lines.add(i + '. ' + a.accountName +
                      ' | 12-month revenue: EUR ' + formatMoney(a.revenue12m) +
                      ' | Why: ' + String.join(a.reasons, '; ') +
                      ' | Owner: ' + (a.ownerName == null ? 'n/a' : a.ownerName));
            i++;
        }
        return String.join(lines, '\n');
    }

    // ---------- helpers ----------

    private static String formatMoney(Decimal d) {
        return d == null ? '0' : d.setScale(0).format();
    }

    @TestVisible
    private static Decimal toDecimal(Object v) {
        if (v == null) {
            return null;
        }
        if (v instanceof Decimal) {
            return (Decimal) v;
        }
        if (v instanceof Integer) {
            return Decimal.valueOf((Integer) v);
        }
        if (v instanceof Long) {
            return Decimal.valueOf((Long) v);
        }
        if (v instanceof Double) {
            return Decimal.valueOf((Double) v);
        }
        try {
            return Decimal.valueOf(String.valueOf(v));
        } catch (Exception e) {
            return null;
        }
    }

    private class ByRevenueDesc implements System.Comparator<AtRiskAccount> {
        public Integer compare(AtRiskAccount x, AtRiskAccount y) {
            Decimal a = x.revenue12m == null ? 0 : x.revenue12m;
            Decimal b = y.revenue12m == null ? 0 : y.revenue12m;
            return a == b ? 0 : (a > b ? -1 : 1);
        }
    }
}
