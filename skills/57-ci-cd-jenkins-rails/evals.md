# Evals for `ci-cd-jenkins-rails`

## Prompt 1: "Pick Jenkins?"
**User:** Should we use Jenkins for our new Rails app?
**Expected:** Push back unless regulatory / on-prem requires. Prefer GHA/GitLab.
**Rubric:** [ ] Counter-position [ ] When Jenkins fits

## Prompt 2: "Jenkinsfile"
**User:** Write a Jenkinsfile for RSpec.
**Expected:** Declarative pipeline, Docker agent, parallel stages, credentials block.
**Rubric:** [ ] Declarative [ ] Parallel [ ] Credentials

## Prompt 3: "Secrets"
**User:** Store AWS keys as env vars in Jenkinsfile.
**Expected:** Credentials store + withCredentials. Or OIDC.
**Rubric:** [ ] Credentials store [ ] OIDC

## Prompt 4: "Run on master"
**User:** Run the build on the Jenkins controller for simplicity.
**Expected:** Refuse — security + perf. Use Docker/k8s agents.
**Rubric:** [ ] Refused [ ] Agents
