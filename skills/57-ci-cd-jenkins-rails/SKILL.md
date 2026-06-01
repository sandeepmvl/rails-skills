---
name: ci-cd-jenkins-rails
description: Jenkins for Rails — Jenkinsfile (declarative pipeline) for RSpec, lint, security, deploy. Agents, credentials, parallel stages, the Blue Ocean UI. Counter-position. If you're greenfield in 2026, prefer GitHub Actions or GitLab CI; Jenkins is for enterprise / on-prem requirements where managed CI isn't allowed. Use when the user mentions Jenkins, Jenkinsfile, declarative pipeline, Blue Ocean, Jenkins agents, or is constrained to self-hosted CI in an enterprise environment.
---

# Jenkins for Rails

> Jenkins is the right answer when corporate / regulatory rules forbid managed CI (some banks, defense, healthcare). For everyone else: GitHub Actions or GitLab CI is faster to set up, better-maintained, and has fewer footguns. This skill shows the minimum viable Jenkinsfile and the trade-offs.

## The opinion

> **If you can use GitHub Actions or GitLab CI: do that instead. Jenkins ROI is poor in 2026 — plugin sprawl, fragile upgrades, Groovy security debt, slow runners by default. If you MUST use Jenkins (regulatory / on-prem constraint), use Declarative Pipelines (not Freestyle, not Scripted), one Jenkinsfile per repo, run agents in Docker, store secrets in the Credentials store (NEVER environment variables), upgrade Jenkins LTS quarterly.**

## When Jenkins is unavoidable

- Air-gapped or strictly on-prem with no managed CI option.
- Heavy compliance environment (some FedRAMP, DoD, certain banks) that won't approve cloud-hosted CI.
- Existing Jenkins fleet you have to integrate with (migration to GHA/GitLab over multiple quarters).

Outside those constraints, the maintenance overhead is hard to justify.

## Pattern 1: Declarative pipeline (the modern default)

```groovy
// Jenkinsfile
pipeline {
  agent {
    docker {
      image 'ruby:3.3'
      args  '-v $HOME/.bundle:/usr/local/bundle'
    }
  }

  options {
    timeout(time: 30, unit: 'MINUTES')
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '30'))
    disableConcurrentBuilds()
  }

  environment {
    RAILS_ENV   = 'test'
    BUNDLE_PATH = 'vendor/bundle'
    IMAGE       = 'registry.example.com/myorg/myapp'
  }

  stages {
    stage('Setup') {
      steps {
        sh 'bundle install --jobs 4'
        sh 'yarn install --frozen-lockfile'
        sh 'bin/rails db:prepare'
      }
    }

    stage('Test') {
      parallel {
        stage('RSpec') {
          steps {
            sh 'bundle exec rspec --format progress --format RspecJunitFormatter --out tmp/rspec.xml'
          }
          post {
            always { junit 'tmp/rspec.xml' }
          }
        }

        stage('RuboCop') {
          steps { sh 'bundle exec rubocop --parallel' }
        }

        stage('Brakeman') {
          steps { sh 'bundle exec brakeman -q --no-pager' }
        }

        stage('bundle-audit') {
          steps { sh 'bundle exec bundle-audit check --update' }
        }
      }
    }

    stage('Build image') {
      when { branch 'main' }
      steps {
        sh 'docker build -t ${IMAGE}:${BUILD_NUMBER} .'
        sh 'docker push ${IMAGE}:${BUILD_NUMBER}'
      }
    }

    stage('Deploy') {
      when { branch 'main' }
      // `input` holds the agent for the entire wait. For long approvals, set
      // `agent none` on this stage and allocate the executor in a nested `node` block
      // after the input resolves so you don't starve the pool.
      input { message 'Deploy to production?'; ok 'Deploy' }
      steps {
        withCredentials([sshUserPrivateKey(credentialsId: 'kamal-deploy', keyFileVariable: 'KAMAL_SSH_KEY')]) {
          sh '''
            eval $(ssh-agent -s)
            ssh-add $KAMAL_SSH_KEY
            bundle exec kamal deploy
          '''
        }
      }
    }
  }

  post {
    failure {
      slackSend channel: '#engineering', color: 'danger',
        message: "Build ${env.JOB_NAME} #${env.BUILD_NUMBER} failed: ${env.BUILD_URL}"
    }
  }
}
```

Key choices:
- **Declarative > Scripted** — less Groovy security debt, easier to lint, restart-on-restart support.
- **Docker agent** — same Ruby version everywhere. No "works on my agent" issues.
- **Parallel stages** — RSpec + lint + security run concurrently.
- **`input`** — manual gate before production deploy.
- **`withCredentials`** — proper secret injection from Jenkins Credentials store. NEVER `env.PASSWORD = '...'`.

## Pattern 2: Postgres + Redis via docker-compose

Declarative pipelines don't have GitLab's `services` keyword. Use docker-compose:

```yaml
# docker-compose.ci.yml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: postgres
  redis:
    image: redis:7
```

```groovy
stage('Start services') {
  steps {
    sh 'docker-compose -f docker-compose.ci.yml up -d'
  }
}

stage('Test') {
  steps {
    sh 'DATABASE_URL=postgres://postgres:postgres@postgres:5432/myapp_test bundle exec rspec'
  }
}

post {
  always { sh 'docker-compose -f docker-compose.ci.yml down -v' }
}
```

Or use the `dockerContainer` step from the docker-pipeline plugin to network containers more cleanly.

## Pattern 3: Credentials management

```groovy
withCredentials([
  string(credentialsId: 'rails-master-key', variable: 'RAILS_MASTER_KEY'),
  usernamePassword(credentialsId: 'docker-registry', usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS'),
  sshUserPrivateKey(credentialsId: 'deploy-ssh', keyFileVariable: 'SSH_KEY')
]) {
  sh '''
    docker login -u $REG_USER -p $REG_PASS
    bundle exec kamal deploy
  '''
}
```

The Credentials Plugin handles encryption + access control + audit log.

**Anti-patterns:**
- Setting `env.AWS_SECRET = '...'` in Jenkinsfile.
- Storing secrets in repository `.jenkins/secrets.json`.
- Using "Inject environment variables" plugin with plaintext.

## Pattern 4: OIDC for cloud

Jenkins LTS 2.387+ supports OIDC ID tokens via the OIDC Provider Plugin. Configure once:

```groovy
withAWS(role: 'arn:aws:iam::123456789012:role/jenkins-deploy', roleAccount: '123456789012', region: 'us-east-1', useNode: true) {
  sh 'aws sts get-caller-identity'
}
```

The IAM trust policy must accept Jenkins' OIDC issuer URL. Stronger than long-lived `AWS_ACCESS_KEY_ID` stored in Credentials.

## Pattern 5: Multibranch pipelines

Set up the job as a "Multibranch Pipeline" in Jenkins UI:
- Discovers branches automatically.
- Runs Jenkinsfile from each branch.
- PR/branch builds visible in Blue Ocean.

Configure branch source:
- GitHub / GitLab plugin → repo URL + credentials.
- Branch discovery: "All branches" or "PRs only."
- Prune dead branches after 7 days.

## Pattern 6: Plugin hygiene

Jenkins ships with ~80 plugins by default. Every plugin is:
- A potential CVE.
- A potential break on Jenkins upgrade.

Audit quarterly. Remove plugins you don't use. Pin remaining ones to specific versions in your `plugins.txt`:

```
configuration-as-code:1771.v323b_a_bb_a_d_a_0a_
git:5.2.2
docker-workflow:572.v950f58993f63
pipeline-utility-steps:2.16.2
```

Upgrade in lockstep with Jenkins LTS releases.

## Pattern 7: Agent strategy

- **Don't run jobs on the controller (master).** Security risk + performance.
- **Use ephemeral agents** — Docker / Kubernetes plugins spin up a fresh agent per build.
- **Static Linux agents** for jobs that need a stable host (rare).

```groovy
agent {
  kubernetes {
    yaml '''
      apiVersion: v1
      kind: Pod
      spec:
        containers:
        - name: ruby
          image: ruby:3.3
          command: [cat]
          tty: true
    '''
  }
}
```

Per-build pods on Kubernetes scale to zero when idle and isolate workloads.

## Pattern 8: Pipeline-as-code best practices

- Jenkinsfile lives in the repo. NEVER configure pipelines through the UI.
- Lint Jenkinsfile in CI:
  ```bash
  jenkins-cli declarative-linter < Jenkinsfile
  ```
- Shared libraries (`@Library`) for cross-repo logic (Slack notification, S3 upload). Don't copy-paste Groovy across 30 repos.

## Pattern 9: Backup + DR

Jenkins state lives on disk (`$JENKINS_HOME`). Backup:
- Snapshot the volume daily.
- Or: ThinBackup plugin → S3.

Practice restore quarterly. "We assume backups work" is how you lose half a year of pipeline history.

## Common mistakes to refuse

- Don't use Scripted Pipeline for new work. Declarative is the standard.
- Don't run jobs on the master / controller node.
- Don't store secrets in environment variables, repo files, or job configs.
- Don't skip Jenkins LTS upgrades. Plugins rot.
- Don't auto-install latest plugins. Pin versions.
- Don't expose Jenkins to the public internet without auth + 2FA + IP allowlist.
- Don't use Jenkins for greenfield work in 2026 if you have a choice.

## When to migrate off Jenkins

Triggers:
- Plugin upgrade breaks pipelines monthly.
- Time-to-feedback > 10 minutes on a small Rails app (something wrong).
- On-call paged for "Jenkins controller down."
- Team morale is bad about CI specifically.

Migration path: write `.github/workflows/ci.yml` mirroring the Jenkinsfile. Run both for 2 weeks. When parity is confirmed, retire the Jenkinsfile.

## See also

- `ci-cd-github-actions-rails` — usually the migration target
- `ci-cd-gitlab-rails` — same
- `kamal-docker-production` — deploy target
- `rspec-testing-pyramid` — what to test
- `rails-security-baseline` — Brakeman + bundle-audit

## Sources

- [Jenkins docs](https://www.jenkins.io/doc/)
- [Declarative Pipeline](https://www.jenkins.io/doc/book/pipeline/syntax/)
- [Credentials Plugin](https://plugins.jenkins.io/credentials/)
- [Kubernetes Plugin](https://plugins.jenkins.io/kubernetes/)
- [OIDC Provider Plugin](https://plugins.jenkins.io/oidc-provider/)
- [Blue Ocean](https://www.jenkins.io/projects/blueocean/)
