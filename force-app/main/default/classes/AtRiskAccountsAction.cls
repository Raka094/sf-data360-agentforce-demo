/**
 * Agentforce custom action (Apex invocable).
 * Answers: "Which at-risk accounts should I call this week?"
 *
 * In Agentforce Builder: New Action > Reference Action Type = Apex >
 * pick "Get At-Risk Accounts To Call".
 */
public with sharing class AtRiskAccountsAction {

    public class Request {
        @InvocableVariable(
            label='Max Results'
            description='How many accounts to return. Use 5 unless the user asks for a different number.')
        public Integer maxResults;

        @InvocableVariable(
            label='Minimum 12-Month Revenue'
            description='Optional. Ignore accounts with 12-month revenue (EUR) below this value.')
        public Decimal minRevenue12m;

        @InvocableVariable(
            label='Only My Accounts'
            description='True when the user asks about "my" accounts. False when the user asks about all accounts.')
        public Boolean onlyMyAccounts;
    }

    public class Response {
        @InvocableVariable(
            label='Summary'
            description='Ranked list of at-risk accounts with revenue at stake, reason and owner. Show this to the user.')
        public String summary;

        @InvocableVariable(
            label='Account Ids'
            description='Salesforce Ids of the returned accounts, in ranked order.')
        public List<Id> accountIds;
    }

    @InvocableMethod(
        label='Get At-Risk Accounts To Call'
        description='Returns accounts at risk of churn (no recent orders or sharp revenue drop), based on Data Cloud order history, ranked by 12-month revenue at stake. Use when the user asks which accounts to call, prioritise or worry about.'
        category='Account Insights')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        AtRiskAccountService service = new AtRiskAccountService();

        for (Request req : requests) {
            Response res = new Response();
            res.accountIds = new List<Id>();
            try {
                List<AtRiskAccountService.AtRiskAccount> accounts =
                    service.getAtRiskAccounts(req.maxResults, req.minRevenue12m, req.onlyMyAccounts);
                res.summary = AtRiskAccountService.toSummary(accounts);
                for (AtRiskAccountService.AtRiskAccount a : accounts) {
                    res.accountIds.add(a.accountId);
                }
            } catch (Exception e) {
                // Give the agent a readable message instead of a hard failure
                res.summary = 'Could not read account insights from Data Cloud: ' + e.getMessage();
            }
            responses.add(res);
        }
        return responses;
    }
}
