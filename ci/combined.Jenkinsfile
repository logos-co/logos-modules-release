#!/usr/bin/env groovy

library 'status-jenkins-lib@v1.10.3'

/* `system` is the flake system (packages.<system>.lgx-portable),
 * `variant` the pkg/<module>__<variant>.lgx suffix the platform job writes. */
PLATFORMS = [
  [name: 'Linux/x86_64',   system: 'x86_64-linux',   variant: 'linux-amd64',
   job: 'logos/logos-modules-release/systems/linux/x86_64/package'],
  [name: 'Linux/aarch64',  system: 'aarch64-linux',  variant: 'linux-arm64',
   job: 'logos/logos-modules-release/systems/linux/aarch64/package'],
  [name: 'macOS/aarch64',  system: 'aarch64-darwin', variant: 'darwin-arm64',
   job: 'logos/logos-modules-release/systems/macos/aarch64/package'],
  [name: 'Windows/x86_64', system: 'x86_64-windows', variant: 'windows-amd64',
   job: 'logos/logos-modules-release/systems/windows/x86_64/package'],
]

targets     = [:]  /* module -> flake systems it targets */
notReleased = [:]  /* module -> reason; retried on the next run */
storage     = [:]  /* module -> STORAGE written by release-module.sh */
published   = [:]  /* module -> release tag */
urls        = [:]  /* platform -> child build URL */
results     = [:]  /* platform -> child build result */

pipeline {
  agent {
    docker {
      label 'linuxcontainer'
      image 'harbor.status.im/infra/ci-build-containers:linux-base-1.0.2'
      args '--volume=/nix:/nix ' +
           '--volume=/etc/nix:/etc/nix '
    }
  }

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
    disableRestartFromStage()
    timeout(time: 180, unit: 'MINUTES')
    buildDiscarder(logRotator(
      numToKeepStr: '10',
      daysToKeepStr: '30',
      artifactNumToKeepStr: '10',
    ))
  }

  parameters {
    string(
      name: 'MODULES',
      description: 'Comma-separated submodule dir names to release. Empty = all.',
      defaultValue: params.MODULES ?: ''
    )
    booleanParam(
      name: 'SKIP_IF_PUBLISHED',
      description: 'Skip modules whose <name>-v<version> release already has .lgx + sidecar.json.',
      defaultValue: params.SKIP_IF_PUBLISHED != null ? params.SKIP_IF_PUBLISHED : true
    )
    booleanParam(
      name: 'SIGN',
      description: 'Sign packages with the release key.',
      defaultValue: params.SIGN != null ? params.SIGN : true
    )
    booleanParam(
      name: 'PUBLISH',
      description: 'Publish GitHub releases. The catalog index is rebuilt by the rebuild-index GitHub workflow on each published release.',
      defaultValue: utils.isReleaseBuild() || (params.PUBLISH ?: false)
    )
    string(
      name: 'STORAGE_NODES_TEST',
      description: 'Comma-separated logos.test storage node base URLs. Empty skips that network.',
      defaultValue: params.STORAGE_NODES_TEST ?: 'https://node-02.gc-us-central1-a.logos.test.status.im',
    )
    string(
      name: 'STORAGE_NODES_DEV',
      description: 'Comma-separated logos.dev storage node base URLs. Empty skips that network.',
      defaultValue: params.STORAGE_NODES_DEV ?: 'https://storage-02.gc-us-central1-a.logos.dev.status.im',
    )
    string(
      name: 'BRANCH',
      description: 'Git branch to build.',
      defaultValue: 'main'
    )
  }

  environment {
    GH_USER = 'logos-co'
    GH_NAME = 'logos-modules-release'
    GH_REPO = "${GH_USER}/${GH_NAME}"
  }

  stages {
    stage('Setup') {
      steps { script {
        def dirs = sh(
          script: "find submodules -mindepth 1 -maxdepth 1 -type d -printf '%f\\n' | sort",
          returnStdout: true
        ).tokenize('\n')
        def all = dirs.findAll { fileExists("submodules/${it}/metadata.json") }
        def ignored = dirs - all
        if (ignored) {
          echo "WARNING: no metadata.json, ignoring: ${ignored.join(', ')}"
        }

        def requested = params.MODULES?.tokenize(', ') ?: all
        def unknown = requested - all
        if (unknown) { error("Unknown modules (or missing metadata.json): ${unknown.join(', ')}") }

        def toBuild = requested
        if (params.SKIP_IF_PUBLISHED) {
          withCredentials([usernamePassword(
            credentialsId:    'status-im-auto',
            usernameVariable: 'GITHUB_USER',
            passwordVariable: 'GH_TOKEN',
          )]) {
            toBuild = nix.develop(
              keepEnv: ['GH_TOKEN', 'GH_REPO'],
              returnStdout: true,
              "scripts/check-published.sh ${requested.join(' ')}"
            ).tokenize('\n')
          }
        }
        if (!toBuild) {
          currentBuild.description = 'All requested modules already published'
        }

        targets.putAll(getModuleTargets(toBuild))
        echo "Building: ${targets.keySet().join(', ') ?: '<none>'}"
        PLATFORMS.each { p ->
          echo "  ${p.name}: ${modulesFor(p).join(', ') ?: '<none>'}"
        }
      } }
    }

    stage('Build') {
      when { expression { targets } }
      steps { script {
        def branches = [:]
        PLATFORMS.each { p ->
          def mods = modulesFor(p)
          if (!mods) { return }
          branches[p.name] = {
            stage(p.name) {
              def child = build(
                job: p.job,
                propagate: false,
                parameters: [
                  string(name: 'MODULES', value: mods.join(',')),
                  string(name: 'BRANCH',  value: params.BRANCH),
                ],
              )
              urls[p.name]    = child.absoluteUrl
              results[p.name] = child.result
              jenkins.setBuildDesc(urls)
              github.statusUpdate(
                context: "jenkins/${p.name}",
                state:   child.result == 'SUCCESS' ? 'SUCCESS' : 'FAILURE',
                message: "${child.result}: ${mods.size()} module(s)",
                url:     child.absoluteUrl,
              )
              /* Copy whatever did build; Merge & Sign catches missing variants. */
              try {
                jenkins.copyArts(child)
              } catch (ex) {
                echo "WARNING: no artifacts from ${p.name} (${child.result}): ${ex.message}"
              }
            }
          }
        }
        parallel(branches)
      } }
    }

    stage('Merge & Sign') {
      when { expression { targets } }
      steps { script {
        def creds = [
          usernamePassword(credentialsId: 'logos-storage-node-auth-test',
                           usernameVariable: 'STORAGE_USER_TEST', passwordVariable: 'STORAGE_PASS_TEST'),
          usernamePassword(credentialsId: 'logos-storage-node-auth-dev',
                           usernameVariable: 'STORAGE_USER_DEV',  passwordVariable: 'STORAGE_PASS_DEV'),
        ]
        if (params.SIGN) {
          creds << file(credentialsId: 'logos-lgx-release-signing-key', variable: 'LGX_SIGNING_KEY')
        }
        withCredentials(creds) {
          withEnv(["REQUESTED_VARIANTS=${PLATFORMS.collect { it.variant }.join(',')}"]) {
            targets.each { m, systems ->
              /* Published versions are immutable - never release with a variant missing. */
              def missing = PLATFORMS
                .findAll { it.system in systems }
                .collect { it.variant }
                .findAll { !fileExists("pkg/${m}__${it}.lgx") }
              if (missing) {
                notReleased[m] = "build failed: ${missing.join(', ')}"
                return
              }

              def status = nix.develop(
                keepEnv: ['LGX_SIGNING_KEY', 'REQUESTED_VARIANTS',
                          'STORAGE_NODES_TEST', 'STORAGE_USER_TEST', 'STORAGE_PASS_TEST',
                          'STORAGE_NODES_DEV',  'STORAGE_USER_DEV',  'STORAGE_PASS_DEV'],
                returnStatus: true,
                "scripts/release-module.sh ${m} pkg released"
              )
              def storageFile = "released/${m}/STORAGE"
              storage[m] = fileExists(storageFile) ? readProperties(file: storageFile) : [:]
              if (status != 0) {
                notReleased[m] = 'packaging failed'
              }
            }
          }
        }
      } }
    }

    stage('Publish Releases') {
      when { expression { targets && params.PUBLISH } }
      steps { script {
        targets.keySet().findAll { !notReleased[it] }.each { m ->
          def out = "released/${m}"
          def tag = readFile("${out}/TAG").trim()
          github.upsertRelease(
            user:    env.GH_USER,
            repo:    env.GH_NAME,
            version: tag,
            name:    readFile("${out}/TITLE").trim(),
            branch:  env.GIT_COMMIT,
            desc:    readFile("${out}/NOTES").trim(),
            files:   (findFiles(glob: "${out}/*.lgx") as List) +
                     (findFiles(glob: "${out}/sidecar.json") as List),
          )
          published[m] = tag
          echo "Published ${tag}"
        }
      } }
    }

    stage('Summary') {
      when { expression { notReleased } }
      steps { script {
        notReleased.each { m, reason -> echo "NOT RELEASED  ${m}: ${reason}" }
        error("Not released: ${notReleased.keySet().join(', ')} (retried on the next run)")
      } }
    }
  }

  post {
    success      { script { github.statusUpdate(context: "jenkins/${params.BRANCH}", state: 'SUCCESS', message: 'Release pipeline passed') } }
    unsuccessful { script { github.statusUpdate(context: "jenkins/${params.BRANCH}", state: 'FAILURE', message: "Release pipeline ${currentBuild.currentResult}") } }
    always { script {
      archiveArtifacts(artifacts: 'released/**, pkg/report__*', allowEmptyArchive: true)
      notifyDiscord()
    } }
    cleanup {
      cleanWs(disableDeferredWipeout: true)
      dir(env.WORKSPACE_TMP) { deleteDir() }
    }
  }
}

/* Returns [module: [system, ...]] for modules with packages.<system>.lgx-portable
 * on at least one platform. The rest go to notReleased. */
def getModuleTargets(List modules) {
  def systems = PLATFORMS.collect { "\"${it.system}\"" }.join(' ')
  writeFile(file: '.lgx-targets.nix', text: """
    p: builtins.filter (s:
      builtins.hasAttr s p &&
      (builtins.tryEval ((builtins.getAttr s p) ? "lgx-portable")).value
    ) [ ${systems} ]
  """)

  def result = [:]
  modules.each { m ->
    try {
      def found = readJSON(text: sh(
        returnStdout: true,
        script: "nix eval --json --impure './submodules/${m}#packages' --apply 'import ./.lgx-targets.nix'"
      )) as List
      if (found) {
        result[m] = found
      } else {
        notReleased[m] = 'no lgx-portable for any platform'
      }
    } catch (ex) {
      echo "ERROR: flake eval failed for ${m}: ${ex.message}"
      notReleased[m] = 'flake eval failed'
    }
  }
  return result
}

def modulesFor(Map platform) {
  return targets.findAll { m, systems -> platform.system in systems }.keySet() as List
}

def notifyDiscord() {
  if (!params.PUBLISH) { return }
  if (!targets && currentBuild.currentResult == 'SUCCESS') { return }

  def lines = []
  if (urls) {
    lines << '**Platforms:**'
    urls.each { name, url -> lines << "[${name}](${url}): `${results[name]}`" }
  }

  def modules = ((targets.keySet() as List) + (notReleased.keySet() as List)).unique()
  def failedNodes = [:]  /* host -> number of modules */
  if (modules) {
    lines << '**Modules:**'
  }
  modules.each { m ->
    def st = storage[m] ?: [:]
    def line = "`${m}`: " + (published[m]   ? "PUBLISHED `${published[m]}`" :
                             notReleased[m] ? "NOT RELEASED (${notReleased[m]})" :
                                              'NOT PUBLISHED')
    if (st) {
      line += ' | storage ' + ['test', 'dev'].collect { net ->
        "${net}: `${(st[net] ?: 'skipped').toUpperCase()}`"
      }.join(', ')
    }
    lines << line

    ['test', 'dev'].each { net ->
      st[net + '_failed']?.tokenize(',')?.each { url ->
        def host = url.replaceAll('^https?://([^/]+).*$', '$1')
        failedNodes[host] = (failedNodes[host] ?: 0) + 1
      }
    }
  }
  if (failedNodes) {
    lines << '**Storage node failures:**'
    failedNodes.each { host, n -> lines << "`${host}`: ${n} module(s)" }
  }

  try {
    discord.send(
      cred:    'discord-logos-releases-webhook',
      descPre: lines.join('\n'),
    )
  } catch (ex) {
    echo "WARNING: Discord notification failed: ${ex.message}"
  }
}
