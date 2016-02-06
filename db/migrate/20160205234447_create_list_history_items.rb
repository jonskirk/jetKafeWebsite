class CreateListHistoryItems < ActiveRecord::Migration
  def change
    create_table :list_history_items do |t|
      t.string :email
      t.string :note

      t.timestamps null: false
    end
  end
end
