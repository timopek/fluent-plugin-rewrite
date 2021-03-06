module Fluent
  class RewriteOutput < Output
    Fluent::Plugin.register_output('rewrite', self)

    # Define `router` method of v0.12 to support v0.10.57 or earlier
    unless method_defined?(:router)
      define_method("router") { Engine }
    end

    config_param :remove_prefix,   :string, :default => nil
    config_param :add_prefix,      :string, :default => nil
    config_param :enable_warnings, :bool,   :default => false

    attr_reader  :rules

    def configure(conf)
      super

      if @remove_prefix
        @removed_prefix_string = @remove_prefix + '.'
        @removed_length = @removed_prefix_string.length
      end
      if @add_prefix
        @added_prefix_string = @add_prefix + '.'
      end

      @rules = conf.elements.select {|element| element.name == 'rule' }.map do |element|
        rule = {}
        element.keys.each do |key|
          # read and throw away to supress unread configuration warning
          rule[key] = element[key]
        end
        rule["regex"] = Regexp.new(element["pattern"]) if element.has_key?("pattern")
        rule
      end
    end

    def start
      super
    end

    def shutdown
      super
    end

    def emit(tag, es, chain)
      _tag = tag.clone

      if @remove_prefix and
        ((tag.start_with?(@removed_prefix_string) && tag.length > @removed_length) || tag == @remove_prefix)
        tag = tag[@removed_length..-1] || ''
      end

      if @add_prefix
        tag = tag && tag.length > 0 ? @added_prefix_string + tag : @add_prefix
      end

      es.each do |time, record|
        filtered_tag, record = rewrite(tag, record)
        if filtered_tag && record && _tag != filtered_tag
          router.emit(filtered_tag, time, record)
        else
          if @enable_warnings
            $log.warn "Can not emit message because the tag(#{tag}) has not changed. Dropped record #{record}"
          end
        end
      end

      chain.next
    end

    def rewrite(tag, record)
      rules.each do |rule|
        tag, record, last = apply_rule(rule, tag, record)

        break  if last
        return if !tag && !record
      end

      [tag, record]
    end

    def apply_rule(rule, tag, record)
      tag_prefix = tag && tag.length > 0 ? "." : ""
      key        = rule["key"]
      pattern    = rule["pattern"]
      last       = nil

      return [tag, record] if !key || !record.has_key?(key)
      return [tag, record] unless pattern

      if matched = record[key].match(rule["regex"])
        return if rule["ignore"]

        if rule["replace"]
          replace = rule["replace"]
          record[key] = record[key].gsub(rule["regex"], replace)
        end

        if rule["append_to_tag"]
          if rule["tag"]
            tag += (tag_prefix + rule["tag"])
          else
            matched.captures.each do |m|
              tag += (tag_prefix + "#{m}")
            end
          end
        end

        if rule["last"]
          last = true
        end
      else
        if rule["append_to_tag"] && rule["fallback"]
          tag += (tag_prefix + rule["fallback"])
        end
      end

      [tag, record, last]
    end
  end
end
