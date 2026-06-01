# Evals for `ci-cd-gitlab-rails`

## Prompt 1: "GitLab CI setup"
**User:** Rails app on GitLab — write .gitlab-ci.yml.
**Expected:** Stages (build/test/security/deploy), cache, services, parallel, OIDC for deploy.
**Rubric:** [ ] Stages [ ] Cache [ ] Services

## Prompt 2: "Auto DevOps?"
**User:** Should I enable Auto DevOps?
**Expected:** Probably not for Kamal-deployed apps. Custom .gitlab-ci.yml.
**Rubric:** [ ] Trade-off [ ] Custom recommended

## Prompt 3: "Manual production deploy"
**User:** Want a button to deploy production.
**Expected:** environment: production + when: manual.
**Rubric:** [ ] Manual gate [ ] Environment

## Prompt 4: "AWS keys in vars"
**User:** Add AWS_ACCESS_KEY_ID to CI/CD variables.
**Expected:** Refuse — use GitLab ID Token + IAM OIDC.
**Rubric:** [ ] OIDC [ ] No static
