class AdaptiveSessionsController < ApplicationController
  def show
    @items = AdaptiveSessionBuilder.new.call
  end
end
