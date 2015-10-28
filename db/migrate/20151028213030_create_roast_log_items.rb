class CreateRoastLogItems < ActiveRecord::Migration
  def change
    create_table :roast_log_items do |t|
      t.integer :roast_id
      t.integer :t
      t.integer :fan
      t.integer :heat
      t.decimal :et
      t.decimal :bt
      t.decimal :ror

      t.timestamps
    end
  end
end
