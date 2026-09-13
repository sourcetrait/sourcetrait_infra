# TODO: SourceTrait Infra

## `lab/base/windowserver`
- bug: usrlay users dir has read-only files
  - fix: update ps1 to change that
- post-install
  - test script (ps)
  - cleanup script (ps)
  - kvm-side: cleanup

## `$XDG_DATA_HOME/sourcetrait/infra/host`
one vm (host) per file; eg, (vm name) `member.ad.lab.infra.toml`
```toml
name = 'member.ad.lab.infra'
image = 'lab/ad/member'
hostname = 'member.ad.lab.infra'
created = 12346
```

deletes any vm configs (by name) that are no longer installed from dir after
each build or on-demand from `infra.nu data clean`





