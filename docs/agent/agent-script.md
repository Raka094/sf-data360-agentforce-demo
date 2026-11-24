# Agent configuration (Agent Script, Version 2)

Exported from the Agentforce Builder code view (`</>`). Only the parts this project added or changed
are shown; the default subagents (General FAQ, Off Topic, Ambiguous Question) are unchanged from the
**Agentforce Employee Agent** template.

To get the full file from your own org:

```bash
sf project retrieve start --metadata AiAuthoringBundle --api-version 66.0
```

## Agent settings

```yaml
system:
    messages:
        welcome: |
            Hi, I'm the Account Insight Agent. I can tell you which customer accounts are at risk and which ones to call first. Try: "Which at-risk accounts should I call this week?"

config:
    agent_label: "Account Insight Agent"
    agent_template: "EmployeeCopilot__AgentforceEmployeeAgent"
    developer_name: "Account_Insight_Agent"
    agent_type: "AgentforceEmployeeAgent"
    description: "Helps sales reps find at-risk accounts using order history from Data Cloud, ranked by revenue at stake."
```

## Router: added route to the new subagent

```yaml
start_agent agent_router:
    label: "Agent Router"
    reasoning:
        actions:
            go_to_GeneralFAQ: @utils.transition to @subagent.GeneralFAQ
            go_to_off_topic: @utils.transition to @subagent.off_topic
            go_to_ambiguous_question: @utils.transition to @subagent.ambiguous_question
            go_to_At_Risk_Account_Outreach: @utils.transition to @subagent.At_Risk_Account_Outreach
```

## Subagent: At-Risk Account Outreach

```yaml
subagent At_Risk_Account_Outreach:
    label: "At-Risk Account Outreach"
    description: "Questions about which customer accounts are at risk of churn, which accounts to call, or which accounts need attention because orders dropped or stopped."
    reasoning:
        instructions: ->
            |- Always use the action "Get At-Risk Accounts To Call" to answer. Never guess account names or numbers.
             - Use 5 results unless the user asks for a different number.
             - If the user says "my accounts", set Only My Accounts to true; otherwise false.
             - Show the result as a numbered list and keep the reason for each account.
             - If no accounts are returned, say so and state the rule that was used.
             - Do not create or change records.
        actions:
            Get_At_Risk_Accounts_To_Call: @actions.Get_At_Risk_Accounts_To_Call
                with maxResults = ...
                with minRevenue12m = ...
                with onlyMyAccounts = ...

    actions:
        Get_At_Risk_Accounts_To_Call:
            label: "Get At-Risk Accounts To Call"
            description: "Returns accounts at risk of churn (no recent orders or a sharp revenue drop), based on Data Cloud order history, ranked by 12-month revenue at stake. Use when the user asks which accounts to call, prioritise or worry about."
            target: "apex://AtRiskAccountsAction"
            inputs:
                maxResults: integer
                    label: "Max Results"
                    is_required: False
                minRevenue12m: number
                    label: "Minimum 12-Month Revenue"
                    is_required: False
                onlyMyAccounts: boolean
                    label: "Only My Accounts"
                    is_required: False
            outputs:
                accountIds: list[id]
                    label: "Account Ids"
                    is_displayable: False
                summary: string
                    label: "Summary"
                    is_displayable: True
```

`...` means the agent fills the value from the conversation (e.g. "top 3" → `maxResults = 3`).

## Why it is set up this way

- **The description routes; the instructions behave.** The router only reads the subagent
  `description` to choose where a question goes. The `instructions` control what happens after.
- **"Never guess" instruction.** Forces the agent to call the action instead of inventing account
  names or numbers.
- **No required inputs.** The agent can call the action straight away without asking follow-up
  questions; defaults live in Apex (5 results, no minimum revenue).
- **Only the summary is displayed.** Account Ids are passed to the agent for follow-up use but not
  shown to the user.
