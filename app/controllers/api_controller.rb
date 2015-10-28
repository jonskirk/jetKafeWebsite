class ApiController < ApplicationController

  # called from the device in polling mode
  # expects param m = machine ID
  #        = 1 for now !!!

  # result codes:
  # 0 = machine ID not recognized
  # 1 = misconfigured request
  # 2 = commence roast
  def get_command
    if !params[:m] || params[:m] != "1"
      render json: {:result => '0'}
      return
    end

    # OK, here's the meat of the thing
    # we want to pass a command to the roaster if one is needed
    # if the user has triggered a profile download, we pass that
    # if the user has triggered a roast, we pass that
    #   - although it has to be said we could just do that with a button on the roaster ...
    # if the user has triggered a settings update, we pass that
    #   - eg stream roast log from roaster to server might be a setting

    # for now we'll just pass 2 = start roast!
    render json: {:result => '2'}
    return

    # if we get here, we didn't recognize the input, so return an error
    render json: {:result => '1'}
  end

  # return a profile as JSON
  def get_profile

  end

  # create a new roast - essentially create a record, and return the ID
  def create_roast

  end

  # log a datapoint in an existing roast
  #
  # we're expecting the following params for now:
  # rid = roast id
  # t in ms
  # bt as a float
  # et as a float
  #
  def log
    item = RoastLogItem.new
    item.roast_id = params[:rid]
    item.t = params[:t]
    item.bt = params[:bt]
    item.et = params[:et]
    item.save

    # 1 = success
    render json: {result: 1}
  end
end
