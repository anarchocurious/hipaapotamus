require 'active_record'

module Hipaapotamus
  class Action < ActiveRecord::Base
    self.table_name = 'hipaapotamus_actions'

    enum action_type: { access: 0, creation: 1, modification: 2, destruction: 3 }

    def agent_class
      agent_type.try(:constantize)
    end

    def agent
      if agent_class.is_a?(Singleton)
        agent_class.instance
      else
        agent_class.find(agent_id)
      end
    end

    def agent=(agent)
      if agent.is_a? Singleton
        self.agent_id = nil
      else
        self.agent_id = agent.id
      end

      self.agent_type = agent.class.name
    end

    def protected_class
      protected_type.try(:constantize)
    end

    def protected
      @protected ||= protected_class.new.tap do |protected|
        if protected_id.present?
          protected.id = protected_id
          protected.reload unless destruction?
        end

        if protected_attributes.present?
          protected.assign_attributes protected_attributes
        end
      end
    end

    def protected=(protected)
      self.protected_id = protected.try(:id)
      self.protected_type = protected.try(:class).try(:name)
      self.protected_attributes = protected.try(:attributes)

      @protected = protected
    end

    def protected_attributes
      JSON.parse(serialized_protected_attributes) if serialized_protected_attributes.present?
    end

    def protected_attributes=(protected_attributes)
      self.serialized_protected_attributes = protected_attributes.try(:to_json)
    end

    validate :not_changed
    validates :agent_type, :protected_type, :protected_attributes, :action_type, :performed_at, presence: true
    validates :action_completed, inclusion: { in: [true, false] }

    class << self
      def bulk_insert(actions)
        if actions.length > 0
          actions.each do |action|
            raise ActiveRecord::RecordInvalid, 'unable to modify existing actions' unless action.new_record?
            raise ActiveRecord::RecordInvalid, action.errors.full_messages.to_sentence unless action.valid?
          end

          attributeses = actions.map(&:attributes)

          now = DateTime.now
          attributeses.each { |attributes| attributes['created_at'] = now } if self.column_names.include?('created_at')
          attributeses.each { |attributes| attributes['updated_at'] = now } if self.column_names.include?('updated_at')

          uniq_keys = attributeses.map { |attributes| attributes.keys }.flatten(1).uniq

          column_names = uniq_keys.map(&:to_s)
          rows = attributeses.map { |attributes| uniq_keys.map { |key| attributes[key] } }

          value_template = "(#{column_names.map{'?'}.join(', ')})"

          value_clauses = rows.map { |values| sanitize_sql_array([value_template, *values]) }
          values_clause = value_clauses.join(', ')

          column_clauses = column_names.map { |column_name| connection.quote_column_name(column_name) }
          columns_clause = "#{connection.quote_column_name(table_name)} (#{column_clauses.join(', ')})"

          insert_statement = "INSERT INTO #{columns_clause} VALUES #{values_clause};"

          connection.execute(insert_statement)
        end
      end
    end

    private

    def not_changed
      unless new_record?
        self.errors.add(:action, 'cannot be changed')
      end
    end
  end
end