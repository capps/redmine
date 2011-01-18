class AddInlineImagesToUserPreferences < ActiveRecord::Migration
  def self.up
    add_column :user_preferences, :inline_images, :boolean, :default=>false
  end

  def self.down
    remove_column :user_preferences, :inline_images
  end
end
