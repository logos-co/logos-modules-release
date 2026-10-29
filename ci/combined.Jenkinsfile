#!/usr/bin/env groovy

library 'status-jenkins-lib@v1.10.3'

urls = [:]

/* platform name -> [url:, result:], for Discord. */
platformResults = [:]

/* module -> STORAGE properties written by release-module.sh. */
storage = [:]

/* module -> published tag. */
published = [:]

/* Every platform the catalog can build. `system` is the flake system
 * (packages.<system>.lgx-portable), `variant` the pkg/<module>__<variant>.lgx
 * suffix the platform job writes. */
PLATFORMS = [
  [name: 'Linux/x86_64',   key: 'Linux',     system: 'x86_64-linux',   variant: 'linux-amd64',
   job: 'logos/logos-modules-release/systems/linux/x86_64/package'],
  [name: 'Linux/aarch64',  key: 'Linux-ARM', system: 'aarch64-linux',  variant: 'linux-arm64',
   job: 'logos/logos-modules-release/systems/linux/aarch64/package'],
  [name: 'macOS/aarch64',  key: 'macOS',     system: 'aarch64-darwin', variant: 'darwin-arm64',
   job: 'logos/logos-modules-release/systems/macos/aarch64/package'],
  [name: 'Windows/x86_64', key: 'Windows',   system: 'x86_64-windows', variant: 'windows-amd64',
   job: 'logos/logos-modules-release/systems/windows/x86_64/package'],
]

/* module -> list of flake systems it targets; filled in Setup. */
targets = [:]

/* module -> reason, for modules that needed a release but didn't get one.
 * They stay unpublished, so the next run retries them. */
notReleased = [:]

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
        ).trim().split('\n') as List
        def all = dirs.findAll { fileExists("submodules/${it}/metadata.json") }
        def ignored = dirs - all
        if (ignored) {
          echo "WARNING: no metadata.json, ignoring: ${ignored.join(', ')}"
        }

        def requested = params.MODULES?.trim() ?
          params.MODULES.split(',').collect { it.trim() }.findAll { it } : all
        def unknown = requested - all
        if (unknown) { error("Unknown modules (or missing metadata.json): ${unknown.join(', ')}") }

        def toBuild = requested
        if (params.SKIP_IF_PUBLISHED) {
          withCredentials([usernamePassword(
            credentialsId:    'status-im-auto',
            usernameVariable: 'GITHUB_USER',
            passwordVariable: 'GH_TOKEN',
          )]) {
            def output = nix.develop(
              keepEnv: ['GH_TOKEN', 'GH_REPO'],
              returnStdout: true,
              "scripts/check-published.sh ${requested.join(' ')}"
            )
            toBuild = output.trim() ? output.trim().split('\n') as List : []
          }
        }

        if (toBuild.isEmpty()) {
          currentBuild.description = 'All requested modules already published'
        }

        targets.putAll(getModuleTargets(toBuild))
        env.BUILD_MODULES = targets.keySet().join(',')
        echo "Building: ${env.BUILD_MODULES ?: '<none>'}"
        PLATFORMS.each { p ->
          echo "  ${p.name}: ${modulesFor(p).join(', ') ?: '<none>'}"
        }
      } }
    }

    stage('Build') {
      when { expression { hasModules() } }
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
              def result = child.result
              github.statusUpdate(
                context: "jenkins/${p.name}",
                state:   result == 'SUCCESS' ? 'SUCCESS' : 'FAILURE',
                message: "${result}: ${mods.size()} module(s)",
                url:     child.absoluteUrl,
              )
              urls[p.key] = child.absoluteUrl
              platformResults[p.name] = [url: child.absoluteUrl, result: result]
              jenkins.setBuildDesc(urls)
              /* Copy whatever did build; modules missing a variant are
               * caught per module in Merge & Sign. */
              try {
                jenkins.copyArts(child)
              } catch (ex) {
                echo "WARNING: no artifacts from ${p.name} (${result}): ${ex.message}"
              }
            }
          }
        }
        parallel(branches)
      } }
    }

    stage('Merge & Sign') {
      when { expression { hasModules() } }
      steps { script {
        def creds = []
        if (params.SIGN) {
          creds << file(credentialsId: 'logos-lgx-release-signing-key', variable: 'LGX_SIGNING_KEY')
        }
        if (params.STORAGE_NODES_TEST?.trim()) {
          creds << usernamePassword(
            credentialsId:    'logos-storage-node-auth-test',
            usernameVariable: 'STORAGE_USER_TEST',
            passwordVariable: 'STORAGE_PASS_TEST',
          )
        }
        if (params.STORAGE_NODES_DEV?.trim()) {
          creds << usernamePassword(
            credentialsId:    'logos-storage-node-auth-dev',
            usernameVariable: 'STORAGE_USER_DEV',
            passwordVariable: 'STORAGE_PASS_DEV',
          )
        }
        withCredentials(creds) {
          withEnv([
            "STORAGE_NODES_TEST=${params.STORAGE_NODES_TEST?.trim() ?: ''}",
            "STORAGE_NODES_DEV=${params.STORAGE_NODES_DEV?.trim() ?: ''}",
            /* Variants a module doesn't build are listed as missing. */
            "REQUESTED_VARIANTS=${PLATFORMS.collect { it.variant }.join(',')}",
          ]) {
            (env.BUILD_MODULES.split(',') as List).each { m ->
              /* All or nothing: never publish a module without a variant
               * it targets - published versions are immutable. */
              def missing = PLATFORMS
                .findAll { it.system in targets[m] }
                .collect { it.variant }
                .findAll { v -> !fileExists("pkg/${m}__${v}.lgx") }
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

              storage[m] = readStorage(m)
              if (status != 0) {
                notReleased[m] = 'packaging failed'
                sh "rm -rf 'released/${m}'"
              }
            }
          }
        }
      } }
    }

    stage('Publish Releases') {
      when { expression { hasModules() && params.PUBLISH } }
      steps { script {
        findFiles(glob: 'released/*/TAG').each { tagFile ->
          def moddir = tagFile.path.replaceAll('/TAG$', '')
          def tag    = readFile(tagFile.path).trim()
          def files  = (findFiles(glob: "${moddir}/*.lgx") as List) +
                       (findFiles(glob: "${moddir}/sidecar.json") as List)
          github.upsertRelease(
            user:    env.GH_USER,
            repo:    env.GH_NAME,
            version: tag,
            name:    readFile("${moddir}/TITLE").trim(),
            branch:  env.GIT_COMMIT,
            desc:    readFile("${moddir}/NOTES").trim(),
            files:   files,
          )
          published[moddir.tokenize('/')[-1]] = tag
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
      if (urls) { jenkins.setBuildDesc(urls) }
      notifyDiscord()
    } }
    cleanup {
      cleanWs(disableDeferredWipeout: true)
      dir(env.WORKSPACE_TMP) { deleteDir() }
    }
  }
}

/* Returns [module: [system, ...]] for every module that targets at least one
 * of PLATFORMS, judged by packages.<system>.lgx-portable in its flake.
 * Modules that fail to evaluate or target nothing go to notReleased. */
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
      def out = sh(
        returnStdout: true,
        script: "nix eval --json --impure './submodules/${m}#packages' --apply 'import ./.lgx-targets.nix'"
      )
      def found = readJSON(text: out.trim()) as List
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

def hasModules() {
  return env.BUILD_MODULES != null && env.BUILD_MODULES != ''
}

def readStorage(String m) {
  def f = "released/${m}/STORAGE"
  return fileExists(f) ? readProperties(file: f) : [:]
}

def storageStatus(String net, Map st) {
  if (!params['STORAGE_NODES_' + net.toUpperCase()]?.trim()) { return 'SKIPPED' }
  switch (st?.get(net)) {
    case 'ok':      return 'SUCCESS'
    case 'partial': return 'PARTIAL'
    case 'failed':  return 'FAILURE'
    default:        return 'NOT RUN'
  }
}

def notifyDiscord() {
  if (!params.PUBLISH) { return }
  if (!hasModules() && currentBuild.currentResult == 'SUCCESS') { return }

  def lines = []
  if (platformResults) {
    lines << '**Platforms:**'
    platformResults.each { name, p ->
      lines << "[${name}](${p.url}): `${p.result}`"
    }
  }

  def modules = ((env.BUILD_MODULES ?: '').tokenize(',') + (notReleased.keySet() as List)).unique()
  def nodeFailures = [:]
  if (modules) {
    lines << '**Modules:**'
    modules.each { m ->
      def st = storage[m] ?: [:]
      def state
      if (published[m])        { state = "PUBLISHED `${published[m]}`" }
      else if (notReleased[m]) { state = "NOT RELEASED (${notReleased[m]})" }
      else                     { state = 'NOT PUBLISHED' }
      def line = "`${m}`: ${state}"
      if (st) {
        line += ' | storage ' + ['test', 'dev'].collect {
          "${it}: `${storageStatus(it, st)}`"
        }.join(', ')
      }
      lines << line
      ['test', 'dev'].each { net ->
        st.get(net + '_failed')?.tokenize(',')?.each { url ->
          def host = url.replaceAll('^https?://', '').replaceAll('/.*$', '')
          nodeFailures[host] = (nodeFailures[host] ?: 0) + 1
        }
      }
    }
  }
  if (nodeFailures) {
    lines << '**Storage node failures:**'
    nodeFailures.each { host, n -> lines << "`${host}`: ${n} module(s)" }
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
