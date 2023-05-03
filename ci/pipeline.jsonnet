local job = import 'job.libsonnet';
local resource = import 'resource.libsonnet';
local resource_type = import 'resource_type.libsonnet';

local repo_source = 'git@github.com:nbycomp/k8s.git';
local username = 'robot$concourse';

local components = [
  {
    name: 'hydra',
    remove_maester: true,
  },
  {
    name: 'keto',
    remove_maester: false,
  },
  {
    name: 'kratos',
    remove_maester: false,
  },
  {
    name: 'oathkeeper',
    remove_maester: true,
  },
];

{
  resource_types: [
    resource_type.chartmuseum,
    {
      name: 'git',
      type: 'registry-image',
      source: {
        repository: 'concourse/git-resource',
        tag: '1.14',
      },
    },
  ],

  resources: [
    resource.repo_pipeline(repo_source) { source+: { branch: 'ci' } },
    resource.repo_ci_tasks,
    resource.repo('task-repo', repo_source, { branch: 'ci' }),
    resource.repo('release-repo', repo_source, {
      commit_filter: {
        include: ['^Release v[0-9]\\+\\.[0-9]\\+\\.[0-9]\\+'],
      },
      disable_ci_skip: true,
    }),
  ] + [
    {
      name: c.name,
      type: 'chartmuseum',
      icon: 'bank',
      source: {
        server_url: 'https://registry.nearbycomputing.com/api/chartrepo/public/charts',
        chart_name: c.name + (if c.remove_maester then '-maesterless' else ''),
        basic_auth_username: username,
        basic_auth_password: '((registry-password))',
        harbor_api: true,
      },
    }
    for c in components
  ],

  jobs: [
    job.update_pipeline,
  ] + [
    {
      name: c.name + '-maesterless',
      public: true,
      serial: true,
      plan: [
        {
          in_parallel: [
            {
              get: 'task-repo',
            },
            {
              get: 'repo',
              resource: 'release-repo',
              trigger: true,
            },
          ],
        },
        {
          task: 'remove-maester',
          file: 'task-repo/ci/remove-maester.yml',
          params: {
            CHART_DIR: 'helm/charts/' + c.name,
          },
        },
        {
          put: c.name,
          params: {
            chart: 'updated-repo/helm/charts/%s/' % c.name,
          },
        },
      ],
    }
    for c in components
    if c.remove_maester
  ] + [
    {
      name: c.name,
      public: true,
      serial: true,
      plan: [
        {
          get: 'repo',
          resource: 'release-repo',
          trigger: true,
        },
        {
          put: c.name,
          params: {
            chart: 'repo/helm/charts/%s/' % c.name,
          },
        },
      ],
    }
    for c in components
    if !c.remove_maester
  ],
}
