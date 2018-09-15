require 'rails_helper'

describe RemoteTheme do
  context '#import_remote' do
    def setup_git_repo(files)
      dir = Dir.tmpdir
      repo_dir = "#{dir}/#{SecureRandom.hex}"
      `mkdir #{repo_dir}`
      `cd #{repo_dir} && git init . `
      `cd #{repo_dir} && git config user.email 'someone@cool.com'`
      `cd #{repo_dir} && git config user.name 'The Cool One'`
      `cd #{repo_dir} && mkdir desktop mobile common assets`
      files.each do |name, data|
        File.write("#{repo_dir}/#{name}", data)
        `cd #{repo_dir} && git add #{name}`
      end
      `cd #{repo_dir} && git commit -am 'first commit'`
      repo_dir
    end

    def about_json(love_color: "FAFAFA", color_scheme_name: "Amazing")
      <<~JSON
        {
          "name": "awesome theme",
          "about_url": "https://www.site.com/about",
          "license_url": "https://www.site.com/license",
          "assets": {
            "font": "assets/awesome.woff2"
          },
          "fields": {
            "color": {
              "target": "desktop",
              "value": "#FEF",
              "type": "color"
            },
            "name": "sam"
          },
          "color_schemes": {
            "#{color_scheme_name}": {
              "love": "#{love_color}"
            }
          }
        }
      JSON
    end

    let :scss_data do
      "@font-face { font-family: magic; src: url($font)}; body {color: $color; content: $name;}"
    end

    let :initial_repo do
      setup_git_repo(
        "about.json" => about_json,
        "desktop/desktop.scss" => scss_data,
        "common/header.html" => "I AM HEADER",
        "common/random.html" => "I AM SILLY",
        "common/embedded.scss" => "EMBED",
        "assets/awesome.woff2" => "FAKE FONT",
        "settings.yaml" => "boolean_setting: true"
      )
    end

    after do
      `rm -fr #{initial_repo}`
    end

    it 'can correctly import a remote theme' do

      time = Time.new('2000')
      freeze_time time

      @theme = RemoteTheme.import_theme(initial_repo)
      remote = @theme.remote_theme

      expect(@theme.name).to eq('awesome theme')
      expect(remote.remote_url).to eq(initial_repo)
      expect(remote.remote_version).to eq(`cd #{initial_repo} && git rev-parse HEAD`.strip)
      expect(remote.local_version).to eq(`cd #{initial_repo} && git rev-parse HEAD`.strip)

      expect(remote.about_url).to eq("https://www.site.com/about")
      expect(remote.license_url).to eq("https://www.site.com/license")

      expect(@theme.theme_fields.length).to eq(7)

      mapped = Hash[*@theme.theme_fields.map { |f| ["#{f.target_id}-#{f.name}", f.value] }.flatten]

      expect(mapped["0-header"]).to eq("I AM HEADER")
      expect(mapped["1-scss"]).to eq(scss_data)
      expect(mapped["0-embedded_scss"]).to eq("EMBED")

      expect(mapped["1-color"]).to eq("#FEF")
      expect(mapped["0-font"]).to eq("")
      expect(mapped["0-name"]).to eq("sam")

      expect(mapped["3-yaml"]).to eq("boolean_setting: true")

      expect(mapped.length).to eq(7)

      expect(@theme.settings.length).to eq(1)
      expect(@theme.settings.first.value).to eq(true)

      expect(remote.remote_updated_at).to eq(time)

      scheme = ColorScheme.find_by(theme_id: @theme.id)
      expect(scheme.name).to eq("Amazing")
      expect(scheme.colors.find_by(name: 'love').hex).to eq('fafafa')

      File.write("#{initial_repo}/common/header.html", "I AM UPDATED")
      File.write("#{initial_repo}/about.json", about_json(love_color: "EAEAEA"))

      File.write("#{initial_repo}/settings.yml", "integer_setting: 32")
      `cd #{initial_repo} && git add settings.yml`

      File.delete("#{initial_repo}/settings.yaml")
      `cd #{initial_repo} && git commit -am "update"`

      time = Time.new('2001')
      freeze_time time

      remote.update_remote_version
      expect(remote.commits_behind).to eq(1)
      expect(remote.remote_version).to eq(`cd #{initial_repo} && git rev-parse HEAD`.strip)

      remote.update_from_remote
      @theme.save
      @theme.reload

      scheme = ColorScheme.find_by(theme_id: @theme.id)
      expect(scheme.name).to eq("Amazing")
      expect(scheme.colors.find_by(name: 'love').hex).to eq('eaeaea')

      mapped = Hash[*@theme.theme_fields.map { |f| ["#{f.target_id}-#{f.name}", f.value] }.flatten]

      expect(mapped["0-header"]).to eq("I AM UPDATED")
      expect(mapped["1-scss"]).to eq(scss_data)

      expect(@theme.settings.length).to eq(1)
      expect(@theme.settings.first.value).to eq(32)

      expect(remote.remote_updated_at).to eq(time)

      # It should be able to remove old colors as well
      File.write("#{initial_repo}/about.json", about_json(love_color: "BABABA", color_scheme_name: "Amazing 2"))
      `cd #{initial_repo} && git commit -am "update"`

      remote.update_from_remote
      @theme.save
      @theme.reload

      scheme_count = ColorScheme.where(theme_id: @theme.id).count
      expect(scheme_count).to eq(1)
    end
  end

  let(:github_repo) do
    RemoteTheme.create!(
      remote_url: "https://github.com/org/testtheme.git",
      local_version: "a2ec030e551fc8d8579790e1954876fe769fe40a",
      remote_version: "21122230dbfed804067849393c3332083ddd0c07",
      commits_behind: 2
    )
  end

  let(:gitlab_repo) do
    RemoteTheme.create!(
      remote_url: "https://gitlab.com/org/repo.git",
      local_version: "a2ec030e551fc8d8579790e1954876fe769fe40a",
      remote_version: "21122230dbfed804067849393c3332083ddd0c07",
      commits_behind: 5
    )
  end

  context "#github_diff_link" do
    it "is blank for non-github repos" do
      expect(gitlab_repo.github_diff_link).to be_blank
    end

    it "returns URL for comparing between local_version and remote_version" do
      expect(github_repo.github_diff_link).to eq(
        "https://github.com/org/testtheme/compare/#{github_repo.local_version}...#{github_repo.remote_version}"
      )
    end

    it "is blank when theme is up-to-date" do
      github_repo.update!(local_version: github_repo.remote_version, commits_behind: 0)
      expect(github_repo.reload.github_diff_link).to be_blank
    end
  end

  context ".out_of_date_themes" do
    let(:remote) { RemoteTheme.create!(remote_url: "https://github.com/org/testtheme") }
    let!(:theme) { Fabricate(:theme, remote_theme: remote) }

    it "finds out of date themes" do
      remote.update!(local_version: "old version", remote_version: "new version", commits_behind: 2)
      expect(described_class.out_of_date_themes).to eq([[theme.name, theme.id]])

      remote.update!(local_version: "new version", commits_behind: 0)
      expect(described_class.out_of_date_themes).to eq([])
    end
  end
end