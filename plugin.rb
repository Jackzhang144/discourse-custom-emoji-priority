# frozen_string_literal: true

# name: discourse-custom-emoji-priority
# about: Puts custom emojis at the top of the emoji picker list
# version: 1.0
# author: Jack Zhang
# # url: https://github.com/Jackzhang144/discourse-custom-emoji-priority

# 声明此插件的主开关设置
# 当管理员访问 /admin/site_settings 时，会显示此设置
# 开启后插件功能生效，关闭后恢复原生行为
enabled_site_setting :custom_emoji_priority_enabled

# after_initialize 是 Discourse 的生命周期钩子
# 在 Rails 应用初始化完成后、请求处理之前执行
# 此时所有 gems、插件、模型都已加载完成
after_initialize do
  # ---------------------------------------------------------
  # 第一步：保存原始 Emoji.load_allowed 方法的引用
  # ---------------------------------------------------------
  # 因为我们即将用 define_singleton_method 覆盖此方法
  # 所以需要先保存原始方法的引用，以便在设置关闭时回退
  # instance_method(:method_name) 获取方法的 UnboundMethod 对象
  # 它可以被绑定到任意对象上执行
  original_load_allowed = Emoji.instance_method(:load_allowed)

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
      # bind(self) 将保存的 UnboundMethod 绑定到当前 Emoji 对象
      # 然后通过 .call 执行调用
      return original_load_allowed.bind(self).call
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
    # 将所有 emoji（标准 + 自定义）按分组聚合
    # group_by(&:group) 返回 Hash，key 是分组名，value 是该分组的 emoji 数组
    # ---------------------------------------------------------
    all_grouped = (standard_emojis + custom_emojis).group_by(&:group)

    # ---------------------------------------------------------
    # 对每个分组内的 emoji 进行排序
    # 排序规则：自定义 emoji 排在前面，标准 emoji 排在后面
    # ---------------------------------------------------------
    all_grouped.each do |group, emojis|
      # sort_by 根据返回值排序，0 排在 1 前面
      # is_custom 判断逻辑：
      #   - created_by.present? 表示从数据库加载的自定义 emoji
      #   - plugin_emoji_names.include?(e.name) 表示由插件注册的自定义 emoji
      all_grouped[group] = emojis.sort_by do |e|
        is_custom = e.created_by.present? || plugin_emoji_names.include?(e.name)
        # true (自定义) -> 0 (排在前面)
        # false (标准) -> 1 (排在后面)
        is_custom ? 0 : 1
      end
    end

    # ---------------------------------------------------------
    # 构建最终结果，保持原有分组顺序
    # ---------------------------------------------------------
    result = []
    # 按标准 emoji 的分组顺序依次添加 emoji 到结果数组
    group_order.each do |group|
      result.concat(all_grouped[group] || [])
    end

    # ---------------------------------------------------------
    # 处理自定义 emoji 特有的分组
    # 有些自定义 emoji 可能属于标准 emoji 中不存在的分组
    # 这些分组需要追加到结果末尾
    # ---------------------------------------------------------
    (all_grouped.keys - group_order).each do |group|
      result.concat(all_grouped[group])
    end

    # ---------------------------------------------------------
    # 最后一步：过滤被禁用的 emoji
    # ---------------------------------------------------------
    if denied_emojis.present?
      # reject 返回新数组，包含所有不在 denied_emojis 中的 emoji
      result.reject { |e| denied_emojis.include?(e.name) }
    else
      result
    end
  end
end
