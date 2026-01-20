# Fleet GitOps

This is the ds repository for using [Fleet](https://fleetdm.com) with a GitOps workflow.

[Why use GitOps?](https://fleetdm.com/guides/sysadmin-diaries-gitops-a-strategic-advantage#basic-article)

## GitHub setup

1. Cloned the [GitHub repository](https://github.com/fleetdm/fleet-gitops), created my own GitHub repository, and pushed my clone to your new repo. 

2. Added `FLEET_URL` and `FLEET_API_TOKEN` secrets to my new repository's secrets. Learned how [here](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions#creating-secrets-for-a-repository). Set `FLEET_URL` to my Fleet instance's URL (ex. https://organization.fleet.com). [Create an API-only user](https://fleetdm.com/docs/using-fleet/fleetctl-cli#create-api-only-user) with the "GitOps" role and set `FLEET_API_TOKEN` to my user's API token.

4. If you are using secrets to manage SSO metadata for Fleet SSO login or MDM SSO login, uncomment lines 22 and 23 in `gitops.sh`.
   - If you are using different variable names for your secrets, edit the appropriate line to reflect the correct variable name. 

5. In GitHub, enabled the `Apply latest configuration to Fleet` GitHub Actions workflow, and ran workflow manually. Now, when anyone pushes a new commit to the default branch, the action will run and update Fleet. For pull requests, the workflow will do a dry run only.

## Configuration options

For all configuration options, go to the [YAML files reference](https://fleetdm.com/docs/using-fleet/gitops) in the Fleet docs.

## Fleet UI

Once you're set up with GitOps in Fleet, you can optionally put the UI in GitOps mode. This prevents me from making changes in the UI that would be overridden by GitOps workflows. 

An admin can enable GitOps mode in **Settings** > **Integrations** > **Change management**.

Note that this is a UI-only setting. API permissions are restricted based on user role.

