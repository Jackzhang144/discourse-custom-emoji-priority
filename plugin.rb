# frozen_string_literal: true

# name: discourse-custom-emoji-priority
# about: Puts custom emojis at the top of the emoji picker list
# version: 1.0
# author: Jackzhang144
# url: https://github.com/Jackzhang144/discourse-custom-emoji-priority

enabled_site_setting :custom_emoji_priority_enabled

DiscourseEvent.on(:site_setting_changed) do |name, _old_value, _new_value|
  if name == :custom_emoji_priority_enabled
    Emoji.clear_cache
    Discourse.request_refresh!
  end
end

after_initialize do
  original_load_allowed = Emoji.method(:load_allowed)

  Emoji.define_singleton_method(:load_allowed) do
    return original_load_allowed.call unless SiteSetting.custom_emoji_priority_enabled

    denied_emojis = Emoji.denied
    standard_emojis = Emoji.load_standard
    custom_emojis = Emoji.load_custom

    # Build a set of plugin-registered emoji names for O(1) lookup
    plugin_emoji_names = Set.new
    Plugin::CustomEmoji.emojis.each do |_group, emojis|
      emojis.each { |name, _url| plugin_emoji_names << name }
    end

    # Precompute group order and indices for O(1) lookup
    group_order = standard_emojis.map(&:group).uniq
    group_index_map = group_order.each_with_index.to_h

    all_emojis = standard_emojis + custom_emojis
    emoji_index_map = all_emojis.each_with_index.to_h

    # Sort: custom emojis first (by group), then standard emojis (preserving original order)
    sorted_emojis = all_emojis.sort_by do |e|
      is_custom = e.created_by.present? || plugin_emoji_names.include?(e.name)
      group_index = group_index_map[e.group] || group_order.length
      [is_custom ? 0 : 1, group_index, emoji_index_map[e]]
    end

    denied_emojis&.any? ? sorted_emojis.reject { |e| denied_emojis.include?(e.name) } : sorted_emojis
  end
end
