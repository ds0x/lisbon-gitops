# ds Fleet GitOps (Declarative Management)

This is the current repository for ds' demo [Fleet](https://fleetdm.com) environment with a GitOps workflow.

> [!NOTE]
> This repo contains traditional mobile device management (MDM) profiles and configurations along with declarative management (DDM)[^1].

[^1]: This repo is titled to match its DNS. Also, Monster Island is actually a peninsula.

[Why use GitOps?](https://fleetdm.com/guides/sysadmin-diaries-gitops-a-strategic-advantage#basic-article)

## How did I make this?

1. Cloned the [GitHub repository](https://github.com/fleetdm/fleet-gitops), created my own GitHub repository, and pushed my clone to my new repo. After that, I've made changes and added several apps, integrations, queries, policies, and profiles.

2. Added `FLEET_URL` and `FLEET_API_TOKEN` secrets to my new repository's secrets. Learned how [here](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions#creating-secrets-for-a-repository) and from an in-person [GitOps workshop](https://www.eventbrite.com/cc/gitops-for-device-management-4104123). Set `FLEET_URL` to my Fleet instance's URL (ex. https://organization.fleet.com). [Created an API-only user](https://fleetdm.com/docs/using-fleet/fleetctl-cli#create-api-only-user) with the "GitOps" role and set `FLEET_API_TOKEN` to that user's API token.

4. If you are using secrets to manage SSO metadata for Fleet SSO login or MDM SSO login, uncomment the SSO metadata lines in `.github/fleet-gitops/gitops.sh`.
   - If you are using different variable names for your secrets, edit the appropriate line to reflect the correct variable name. 

5. In GitHub, enabled the `Apply latest configuration to Fleet` GitHub Actions workflow, and first ran the workflow manually. Now, when anyone pushes a new commit to the default branch, the action will run and update Fleet. For pull requests, the workflow will do a dry run only.

## Configuration options

For all configuration options, go to the [YAML files reference](https://fleetdm.com/docs/using-fleet/gitops) in the Fleet docs.

## Fleet UI

Once you're set up with GitOps in Fleet, you can optionally put the UI in GitOps mode. This prevents me from making changes in the UI that would be overridden by GitOps workflows. 

An admin can enable GitOps mode in **Settings** > **Integrations** > **Change management**.

Note that this is a UI-only setting. API permissions are restricted based on user role.

Questions? Check out [the official docs](https://fleetdm.com/docs) or on [the #fleet channel on MacAdmins Slack](https://macadmins.slack.com/archives/C0214NELAE7).
