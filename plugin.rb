# frozen_string_literal: true

# name: discourse-custom-emoji-priority
# about: Puts custom emojis at the top of the emoji picker list
# version: 1.0
# author: Jack Zhang
# url: https://github.com/Jackzhang144/discourse-custom-emoji-priority

# 声明此插件的主开关设置
# 当管理员访问 /admin/site_settings 时，会显示此设置
# 开启后插件功能生效，关闭后恢复原生行为
enabled_site_setting :custom_emoji_priority_enabled

# 监听站点设置变化事件，当插件开关变化时清除 Emoji 缓存
DiscourseEvent.on(:site_setting_changed) do |name, _old_value, _new_value|
  if name == :custom_emoji_priority_enabled
    Emoji.clear_cache
    Discourse.request_refresh!
  end
end

# after_initialize 是 Discourse 的生命周期钩子
# 在 Rails 应用初始化完成后、请求处理之前执行
# 此时所有 gems、插件、模型都已加载完成
after_initialize do
  # ---------------------------------------------------------
  # 第一步：保存原始 Emoji.load_allowed 方法的引用
  # ---------------------------------------------------------
  # 因为我们即将用 define_singleton_method 覆盖此方法
  # 所以需要先保存原始方法的引用，以便在设置关闭时回退
  # method(:method_name) 获取类方法的 Method 对象
  # instance_method(:method_name) 只能获取实例方法，无法获取类方法
  original_load_allowed = Emoji.method(:load_allowed)

  # ---------------------------------------------------------
  # 第二步：定义我们自定义的 load_allowed 方法
  # ---------------------------------------------------------
  # define_singleton_method 为 Emoji 类添加一个单例方法
  # 这样不会影响其他地方的 Emoji 类行为
  Emoji.define_singleton_method(:load_allowed) do
    # ---------------------------------------------------------
    # 检查插件设置是否开启
    # SiteSetting 是 Discourse 提供的全局设置访问器
    # ---------------------------------------------------------
    unless SiteSetting.custom_emoji_priority_enabled
      # 设置关闭时，调用原始的 load_allowed 方法并返回结果
      # Method 对象可以直接调用，不需要 bind
      return original_load_allowed.call
    end

    # ---------------------------------------------------------
    # 以下是自定义优先级排序逻辑
    # ---------------------------------------------------------

    # 获取被禁用的 emoji 名称列表（用于后续过滤）
    denied_emojis = Emoji.denied

    # 加载标准 emoji（内置的 emoji）
    standard_emojis = Emoji.load_standard

    # 加载自定义 emoji（用户上传的 emoji）
    custom_emojis = Emoji.load_custom

    # ---------------------------------------------------------
    # 构建插件注册的 emoji 名称集合，用于快速查找
    # Plugin::CustomEmoji 是 Discourse 核心提供的插件 emoji 注册表
    # ---------------------------------------------------------
    plugin_emoji_names = Set.new
    Plugin::CustomEmoji.emojis.each do |_group, emojis|
      # emojis 是一个 Hash，key 是 emoji 名称，value 是 URL
      emojis.each { |name, _url| plugin_emoji_names << name }
    end

    # ---------------------------------------------------------
    # 从标准 emoji 中提取分组顺序
    # Emoji 有多个分组，如 "smile", "people", "animals" 等
    # 我们希望保持这个顺序不变
    # ---------------------------------------------------------
    group_order = standard_emojis.map(&:group).uniq

    # ---------------------------------------------------------
    # 将所有 emoji（标准 + 自定义）混合后排序
    # 排序规则：
    #   1. 所有自定义 emoji 排在所有标准 emoji 前面
    #   2. 自定义 emoji 之间按分组顺序排列
    #   3. 标准 emoji 之间保持原有顺序
    # ---------------------------------------------------------
    all_emojis = standard_emojis + custom_emojis

    sorted_emojis = all_emojis.sort_by do |e|
      is_custom = e.created_by.present? || plugin_emoji_names.include?(e.name)
      group_index = group_order.index(e.group) || group_order.length
      # 自定义 emoji: [0, group_index, position]
      # 标准 emoji:   [1, group_index, position]
      # 这样所有自定义 emoji 会排在所有标准 emoji 前面
      [is_custom ? 0 : 1, group_index, all_emojis.index(e)]
    end

    # ---------------------------------------------------------
    # 最后一步：过滤被禁用的 emoji
    # ---------------------------------------------------------
    if denied_emojis.present?
      # reject 返回新数组，需要赋值给 result
      sorted_emojis = sorted_emojis.reject { |e| denied_emojis.include?(e.name) }
    end
    sorted_emojis
  end
end
