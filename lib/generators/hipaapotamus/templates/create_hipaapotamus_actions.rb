class CreateHipaapotamusActions < ActiveRecord::Migration
  def change
    create_table :hipaapotamus_actions do |t|
      t.integer :agent_id
      t.string :agent_type, null: false

      t.integer :protected_id, null: false
      t.string :protected_type, null: false
      t.json :protected_attributes, null: false

      t.integer :action_type, null: false

      t.datetime :performed_at, null: false
      t.datetime :created_at, null: false
    end
  end
end