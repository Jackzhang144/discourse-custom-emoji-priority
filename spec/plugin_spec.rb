# frozen_string_literal: true

describe "Custom Emoji Priority Plugin" do
  before { SiteSetting.custom_emoji_priority_enabled = true }
  after { SiteSetting.custom_emoji_priority_enabled = false }

  before { Emoji.clear_cache }
  after { Emoji.clear_cache }

  after { Plugin::CustomEmoji.clear_cache }

  let(:plugin_emoji_names) do
    Plugin::CustomEmoji.emojis.values.flat_map(&:keys)
  end

  # Pure standard emoji = not created_by (db) and not in plugin registry
  let(:standard_emoji_names) do
    Emoji.load_standard.reject { |e| e.created_by.present? || plugin_emoji_names.include?(e.name) }.map(&:name)
  end

  describe "when disabled" do
    before do
      SiteSetting.custom_emoji_priority_enabled = false
      Emoji.clear_cache
    end

    it "load_allowed returns combined emojis without priority sorting" do
      allowed_names = Emoji.load_allowed.map(&:name)
      standard_names = Emoji.load_standard.map(&:name)
      custom_names = Emoji.load_custom.map(&:name)

      expect(allowed_names & standard_names).to eq(standard_names)
      expect(allowed_names & custom_names).to eq(custom_names)
      expect(allowed_names).not_to include(*Emoji.denied)
    end
  end

  describe "when enabled" do
    it "puts database custom emojis before standard emojis" do
      allowed = Emoji.load_allowed
      allowed_names = allowed.map(&:name)

      db_custom_names = Emoji.load_custom.select { |e| e.created_by.present? }.map(&:name)
      pure_standard_names = standard_emoji_names

      # Find the last custom emoji and first standard emoji positions
      last_custom_idx = db_custom_names.map { |n| allowed_names.index(n) }.max
      first_standard_idx = pure_standard_names.map { |n| allowed_names.index(n) }.min

      expect(last_custom_idx).to be < first_standard_idx
    end

    it "puts plugin-registered emojis before standard emojis" do
      Plugin::CustomEmoji.register("test_plugin_emoji", "/public/test.png", "test_group")
      Emoji.clear_cache

      allowed = Emoji.load_allowed
      allowed_names = allowed.map(&:name)

      plugin_names = plugin_emoji_names
      pure_standard_names = standard_emoji_names

      # Plugin emoji should appear before any pure standard emoji
      plugin_indices = plugin_names.map { |n| allowed_names.index(n) }
      standard_indices = pure_standard_names.map { |n| allowed_names.index(n) }

      expect(plugin_indices.min).to be < standard_indices.min
    end

    it "still filters out denied emojis" do
      SiteSetting.emoji_deny_list = "peach"
      Emoji.clear_cache

      allowed_names = Emoji.load_allowed.map(&:name)

      expect(allowed_names).not_to include("peach")
    end

    it "maintains standard emojis relative order within each group" do
      allowed = Emoji.load_allowed
      allowed_standard_names =
        allowed
          .select { |e| standard_emoji_names.include?(e.name) }
          .group_by(&:group)
          .transform_values { |group_emojis| group_emojis.map(&:name) }

      original_standard =
        Emoji
          .load_standard
          .reject { |e| e.created_by.present? || plugin_emoji_names.include?(e.name) }
          .group_by(&:group)
          .transform_values { |group_emojis| group_emojis.map(&:name) }

      original_standard.each do |group, names|
        expect(allowed_standard_names[group]).to eq(names),
          "Standard emoji order in group '#{group}' was changed"
      end
    end
  end
end
