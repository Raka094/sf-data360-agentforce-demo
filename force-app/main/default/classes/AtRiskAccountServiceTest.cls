@IsTest
private class AtRiskAccountServiceTest {

    /** Fake Data Cloud client: returns whatever rows the test gives it. */
    private class FakeDataCloud implements IDataCloudQuery {
        List<Map<String, Object>> rows;
        String lastSql;
        Boolean fail = false;
        FakeDataCloud(List<Map<String, Object>> rows) { this.rows = rows; }
        public List<Map<String, Object>> query(String sql) {
            lastSql = sql;
            if (fail) {
                throw new CalloutException('Data Cloud unavailable');
            }
            return rows;
        }
    }

    private static Map<String, Object> row(String accNumber, Decimal rev12, Decimal last90, Decimal prev90, Integer days) {
        return new Map<String, Object>{
            'account_number' => accNumber,
            'revenue_12m' => rev12,
            'revenue_last_90d' => last90,
            'revenue_prev_90d' => prev90,
            'days_since_last_order' => days
        };
    }

    @TestSetup
    static void setup() {
        insert new List<Account>{
            new Account(Name = 'Healthy GmbH', AccountNumber = 'ACC-1'),
            new Account(Name = 'Quiet AG', AccountNumber = 'ACC-2'),
            new Account(Name = 'Declining KG', AccountNumber = 'ACC-3'),
            new Account(Name = 'Small Quiet GmbH', AccountNumber = 'ACC-4')
        };
    }

    private static Map<String, Id> ids() {
        Map<String, Id> m = new Map<String, Id>();
        for (Account a : [SELECT Id, Name FROM Account]) {
            m.put(a.Name, a.Id);
        }
        return m;
    }

    private static final Map<String, String> NUM = new Map<String, String>{
        'Healthy GmbH' => 'ACC-1', 'Quiet AG' => 'ACC-2', 'Declining KG' => 'ACC-3', 'Small Quiet GmbH' => 'ACC-4'
    };

    @IsTest
    static void returnsOnlyAtRiskAccountsRankedByRevenue() {
        FakeDataCloud fake = new FakeDataCloud(new List<Map<String, Object>>{
            row(NUM.get('Healthy GmbH'), 500000, 120000, 110000, 5),     // healthy
            row(NUM.get('Quiet AG'),     200000, 0,      40000,  95),     // gone quiet
            row(NUM.get('Declining KG'), 300000, 20000,  80000,  10),     // -75 %
            row(NUM.get('Small Quiet GmbH'), 5000, 0,    1000,   120)     // quiet but small
        });
        AtRiskAccountService.queryClient = fake;

        Test.startTest();
        List<AtRiskAccountService.AtRiskAccount> result =
            new AtRiskAccountService().getAtRiskAccounts(5, 10000, false);
        Test.stopTest();

        Assert.areEqual(2, result.size(), 'Healthy and small accounts must be excluded');
        Assert.areEqual('Declining KG', result[0].accountName, 'Highest revenue at stake first');
        Assert.areEqual('Quiet AG', result[1].accountName);
        Assert.isTrue(result[0].reasons[0].contains('Revenue down 75%'), result[0].reasons[0]);
        Assert.isTrue(result[1].reasons[0].contains('No order for 95 days'), result[1].reasons[0]);
        Assert.isTrue(fake.lastSql.contains(DataCloudNames.CI_OBJECT), 'Query must read the calculated insight');
    }

    @IsTest
    static void respectsMaxResults() {
        AtRiskAccountService.queryClient = new FakeDataCloud(new List<Map<String, Object>>{
            row(NUM.get('Quiet AG'),     200000, 0,     40000, 95),
            row(NUM.get('Declining KG'), 300000, 20000, 80000, 10)
        });
        List<AtRiskAccountService.AtRiskAccount> result =
            new AtRiskAccountService().getAtRiskAccounts(1, null, true);
        Assert.areEqual(1, result.size());
        Assert.areEqual('Declining KG', result[0].accountName);
    }

    @IsTest
    static void ignoresBlankAndUnknownAccountNumbers() {
        AtRiskAccountService.queryClient = new FakeDataCloud(new List<Map<String, Object>>{
            row('ACC-UNKNOWN', 200000, 0, 40000, 95),          // at risk, but no CRM account
            new Map<String, Object>{ 'account_number' => '  ', 'revenue_12m' => 1 },
            new Map<String, Object>{ 'account_number' => null }
        });
        Assert.areEqual(0, new AtRiskAccountService().getAtRiskAccounts(5, 0, false).size());
    }

    @IsTest
    static void summaryHandlesEmptyAndFilledLists() {
        Assert.isTrue(AtRiskAccountService.toSummary(new List<AtRiskAccountService.AtRiskAccount>())
            .startsWith('No at-risk accounts'));

        AtRiskAccountService.AtRiskAccount a = new AtRiskAccountService.AtRiskAccount();
        a.accountName = 'Quiet AG';
        a.revenue12m = 200000;
        a.reasons.add('No order for 95 days');
        String s = AtRiskAccountService.toSummary(new List<AtRiskAccountService.AtRiskAccount>{ a });
        Assert.isTrue(s.contains('1. Quiet AG'), s);
        Assert.isTrue(s.contains('Owner: n/a'), s);
    }

    @IsTest
    static void toDecimalConvertsCommonTypes() {
        Assert.areEqual(Decimal.valueOf(5), AtRiskAccountService.toDecimal(5));
        Assert.areEqual(Decimal.valueOf(5), AtRiskAccountService.toDecimal(5L));
        Assert.areEqual(5.5, AtRiskAccountService.toDecimal(5.5d));
        Assert.areEqual(7.25, AtRiskAccountService.toDecimal('7.25'));
        Assert.isNull(AtRiskAccountService.toDecimal('abc'));
        Assert.isNull(AtRiskAccountService.toDecimal(null));
    }

    @IsTest
    static void actionReturnsSummaryAndIds() {
        Map<String, Id> acc = ids();
        AtRiskAccountService.queryClient = new FakeDataCloud(new List<Map<String, Object>>{
            row(NUM.get('Quiet AG'), 200000, 0, 40000, 95)
        });
        AtRiskAccountsAction.Request req = new AtRiskAccountsAction.Request();
        req.maxResults = 5;

        List<AtRiskAccountsAction.Response> res =
            AtRiskAccountsAction.run(new List<AtRiskAccountsAction.Request>{ req });

        Assert.areEqual(1, res.size());
        Assert.areEqual(acc.get('Quiet AG'), res[0].accountIds[0]);
        Assert.isTrue(res[0].summary.contains('Quiet AG'), res[0].summary);
    }

    @IsTest
    static void actionReturnsReadableErrorWhenDataCloudFails() {
        FakeDataCloud fake = new FakeDataCloud(new List<Map<String, Object>>());
        fake.fail = true;
        AtRiskAccountService.queryClient = fake;

        List<AtRiskAccountsAction.Response> res =
            AtRiskAccountsAction.run(new List<AtRiskAccountsAction.Request>{ new AtRiskAccountsAction.Request() });

        Assert.isTrue(res[0].summary.startsWith('Could not read account insights'), res[0].summary);
    }

    @IsTest
    static void parserMapsColumnsByPosition() {
        Map<String, Integer> positions = new Map<String, Integer>{ 'Revenue_12M' => 1, 'crm_account_id' => 0 };
        List<Map<String, Object>> rows = DataCloudQueryService.toMaps(
            positions, new List<List<Object>>{ new List<Object>{ '001xx', 42 } });
        Assert.areEqual('001xx', rows[0].get('crm_account_id'));
        Assert.areEqual(42, rows[0].get('revenue_12m'), 'Keys must be lower-cased');
        Assert.areEqual(0, DataCloudQueryService.toMaps(positions, null).size());
    }
}
