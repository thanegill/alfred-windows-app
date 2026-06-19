require 'json'

# Builds the Script Filter JSON that Alfred expects back from a workflow input.
# https://www.alfredapp.com/help/workflows/inputs/script-filter/json/
class Feedback
  attr_accessor :items

  def initialize
    @items = []
  end

  def add_item(opts = {})
    return if opts[:title].nil?

    item = {
      title: opts[:title],
      subtitle: opts[:subtitle] || '',
      arg: opts[:arg] || opts[:title],
      autocomplete: opts[:autocomplete] || opts[:title],
      # Default to actionable; pass valid: false for informational rows.
      valid: opts.fetch(:valid, true),
      icon: { path: opts.dig(:icon, :name) || 'icon.png' }
    }
    item[:icon][:type] = 'fileicon' if opts.dig(:icon, :type) == 'fileicon'
    item[:type] = 'file' if opts[:type] == 'file'

    @items << item
  end

  # No uid is emitted: Alfred preserves the order items are returned in only
  # when uid is absent, which keeps the bookmarks in the app's own order.
  def to_json(*_args)
    JSON.pretty_generate(items: @items)
  end
end
