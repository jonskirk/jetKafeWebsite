include ActionView::Helpers::NumberHelper

class PagesController < ApplicationController
  def home
  end

  def createchart

    @title = params[:title]
    @subtitle = "#{params[:by].upcase}, #{Time.now.strftime("%Y-%m-%d")}"
    @offset = 0 # t when heat first applied --> now done in the Arduino code
    @setpoint = 300
    @init_i = params[:start].to_i
    @Kp = params[:Kp].to_f
    @Ki = params[:Ki].to_f / 10
    @Kd = params[:Kd].to_f * 10

    count = 0
    max_t_measured = 0
    max_BT_measured = 0

    # create the profile
    profile = RoastProfile.new
    params[:target_dry_time].blank? ?
        profile.target_dry_time = 180000.0 : profile.target_dry_time = params[:target_dry_time].to_f
    params[:target_Maillard_time].blank? ?
        profile.target_Maillard_time = 180000.0 :
        profile.target_Maillard_time = params[:target_Maillard_time].to_f
    params[:target_dev_time].blank? ?
        profile.target_dev_time = 180000.0 :
      profile.target_dev_time = params[:target_dev_time].to_f
    params[:target_drop_temp].blank? ?
        profile.target_drop_temp = 430 :
        profile.target_drop_temp = params[:target_drop_temp].to_f

    # set up the chart specifications
    @chart = Chart.new
    @chart.show_BT = true
    @chart.show_ET = true
    @chart.show_fan = false
    @chart.show_heat = true
    @chart.show_PID = false
    @chart.show_BT_ROR = false
    @chart.show_BT_ROR_M = true
    @chart.show_ET_ROR = false
    #@chart.PID_start = params[:pid_start].to_i
    @chart.PID_end = 10000000

    max_t = 2000000

    # CSS for the tables
    @style = "<style>.datatable { border: solid 1px gray; border-collapse: collapse;}
              .datatable td,th { border: solid 1px gray; text-align:center; padding:5px;}</style>".html_safe

    # our profile data is in params[:profile], which is a text string
    datatable = "<table class='datatable'>#{LogEntry.get_html_header}".html_safe
    @data = "".html_safe
    line = ""
    lastentry = nil

    minute = 0
    temp_by_minute = []

    params[:profile].each_char do |c|
      if c == "\n"
        # process whatever we have in line

        # is this the PID start line?
        if line.include? "PID initialized"
          # so the next entry is the first PID
          # which means actualy the one after that is the first to use the result
          # cycle time is 600ms, so put us before the right one
          @chart.PID_start = lastentry.t + 1000
        end

        # are we ending PID input
        if !lastentry.nil? && (@chart.PID_end > lastentry.t) && (line.include? "EC3") # end of cycle time
          @chart.PID_end = lastentry.t
        end

        entry = process_line(line, lastentry)
        #@log << "Line: #{line}, data: #{data}<br />".html_safe
        if entry.nil?
          # if this was a comment or other line, just discard it
          line = ""
        else !entry.nil?
          datatable << entry.get_html_tr
          @data << entry.get_data(@chart)

          # store our summary data
          profile.update(entry)

          # break out if we've hit our upper time limit
          break if entry.t >= max_t

          line = ""
          lastentry = entry

          count += 1
          max_t_measured = entry.t
          max_BT_measured = entry.BT if entry.BT > max_BT_measured

          # record the temps if we are passing a minute
          if entry.t > minute * 60000 && temp_by_minute[minute].nil?
            temp_by_minute[minute] = entry.BT
            minute += 1
          end
        end
      else
        line << c
      end
    end
    datatable << "</table>".html_safe

    # now display the summary data
    @log = "Entry count: #{count}<br />
            Max t: #{max_t_measured}<br />
            Max BT: #{max_BT_measured}<br />
            Temp by minute: #{temp_by_minute}<br />
            Average ROR for min #{get_average_ror(temp_by_minute)}<br/>".html_safe
    @log << "PID Init I: #{@init_i} Kp: #{@Kp} Ki: #{@Ki*10} Kd: #{@Kd} <br />".html_safe if @chart.show_PID
    @log << "Average cycle time: #{max_t_measured / count}ms
            <br /><br />
            #{profile.to_html}<br /><br />".html_safe

    # finally display the full data in easily-copyable form
    @log << "#{datatable}".html_safe

    render :chart
  end

  def get_average_ror(temp_array)
    i = 1
    s = ""
    while i < temp_array.length do
      ror = (temp_array[i] - temp_array[i-1] ) / 60
      s += ", " if i > 1
      s += "#{i}: #{ror.round(2)}"
      i += 1
    end
    s
  end

  def process_line(line, lastentry)
    # if the line doesn't start with "Time: " it's a command or comment line
    # for now, ignore it
    if !line.include? "Time: "
      return nil
    end

    # the general format is
    # Time: 81 Fan: 10 Heat: 0 Ambient: 73.2 ET: 75.7 BT: 73.3
    #
    # we want to create a data row of the form
    # [time,ET,BT,ET-ROR,BT-ROR]

    entry = LogEntry.new
    entry.offset = @offset
    entry.t = line.match(/Time: ([^ ]*)/).captures[0].to_i
    entry.heat = line.match(/Heat: ([^ ]*)/).captures[0].to_i
    entry.fan = line.match(/Fan: ([^ ]*)/).captures[0].to_i
    entry.ET = line.match(/ET: ([^ ]*)/).captures[0].to_f
    entry.BT = line.match(/BT: ([^ ]*)/).captures[0].to_f
    ror = line.match(/ROR: ([^ ]*)/)
    entry.BT_ROR_M = ror.captures[0].to_f if !ror.nil?
    entry.get_ROR(lastentry) if !lastentry.nil?
    if !lastentry.nil? &&
        !@chart.PID_start.nil? && entry.t >= @chart.PID_start &&
        !@chart.PID_end.nil? && entry.t < @chart.PID_end
      entry.get_PID(lastentry.PID, @init_i, @setpoint, @Kp, @Ki, @Kd)
    end

    entry
  end
end

# single place to put specifications for the chart
#
class Chart
  attr_accessor :show_ET_ROR, :show_BT_ROR, :show_fan, :show_heat, :show_BT, :show_ET, :show_BT_ROR_M,
                :show_PID, :PID_start, :PID_end
end

class RoastProfile
  attr_accessor :dry_time, :FC_time, :Maillard_time, :dev_time, :roast_time, :drop_temp,
                :target_dry_time, :target_Maillard_time, :target_dev_time, :target_drop_temp

  def to_html
    "<table class='datatable'>
        <tr>
          <th>&nbsp;</th>
          <th colspan=2>Actual</th>
          <th colspan=2>Target</th>
          <th>Error</th>
        </tr>
        <tr>
          <td colspan=6 style='text-align:left;'>
            287F : target #{(@target_dry_time/1000).round}s : actual #{@dry_time.nil? ? "-" : @dry_time/1000}s (#{(@dry_time.nil? || @target_dry_time.nil?) ?
        "-" : number_to_percentage((@dry_time - @target_dry_time)*100 / @target_dry_time, precision: 1) })<br />
            400F : target #{(@target_Maillard_time/1000).round}s : actual #{@Maillard_time.nil? ? "-" : @Maillard_time/1000}s (#{(@Maillard_time.nil? || @target_Maillard_time.nil?) ?
        "-" : number_to_percentage((@Maillard_time - @target_Maillard_time)*100 / @target_Maillard_time, precision: 1) })<br />
            440F : target #{(@target_dev_time/1000).round}s : actual #{@dev_time.nil? ? "-" : @dev_time/1000}s (#{(@dev_time.nil? || @target_dry_time.nil?) ?
        "-" : number_to_percentage((@dev_time - @target_dev_time)*100 / @target_dev_time, precision: 1) })<br />
          </td>
        </tr>
        <tr>
          <td>Drying time:</td>
          <td>#{@dry_time.nil? ? "-" : @dry_time/1000} (s)</td>
          <td>#{@dry_time.nil? ? "-" : (@dry_time.to_f/1000/60).round(1)} (min)</td>
          <td>#{@target_dry_time.nil? ? "-" : @target_dry_time/1000} (s)</td>
          <td>#{@target_dry_time.nil? ? "-" : (@target_dry_time.to_f/1000/60).round(1)} (min)</td>
          <td align=center>#{(@dry_time.nil? || @target_dry_time.nil?) ?
                  "-" : number_to_percentage((@dry_time - @target_dry_time)*100 / @target_dry_time, precision: 1) }</td>
        </tr>
        <tr>
          <td>Time in Maillard:</td>
          <td>#{@Maillard_time.nil? ? "-" : @Maillard_time/1000} (s)</td>
          <td>#{@Maillard_time.nil? ? "-" : (@Maillard_time.to_f/1000/60).round(1)} (min)</td>
          <td>#{@target_Maillard_time.nil? ? "-" : @target_Maillard_time/1000} (s)</td>
          <td>#{@target_Maillard_time.nil? ? "-" : (@target_Maillard_time.to_f/1000/60).round(1)} (min)</td>
          <td align=center>#{(@Maillard_time.nil? || @target_Maillard_time.nil?) ?
                  "-" : number_to_percentage((@Maillard_time - @target_Maillard_time)*100 / @target_Maillard_time, precision: 1) }</td>
       </tr>
        <tr><td>Total time to FC:</td>
          <td>#{@FC_time.nil? ? "-" : @FC_time/1000} (s)</td>
          <td>#{@FC_time.nil? ? "-" : (@FC_time.to_f/1000/60).round(1)} (min)</td>
          <td>&nbsp;</td>
          <td>&nbsp;</td>
          <td>&nbsp;</td>
        </tr>
        <tr>
          <td>Dev time:</td>
          <td>#{@dev_time.nil? ? "-" : @dev_time/1000} (s)</td>
          <td>#{@dev_time.nil? ? "-" : (@dev_time.to_f/1000/60).round(1)} (min)</td>
          <td>#{@target_dev_time.nil? ? "-" : @target_dev_time/1000} (s)</td>
          <td>#{@target_dev_time.nil? ? "-" : (@target_dev_time.to_f/1000/60).round(1)} (min)</td>
          <td align=center>#{(@dev_time.nil? || @target_dev_time.nil?) ?
                  "-" : number_to_percentage((@dev_time - @target_dev_time)*100 / @target_dev_time, precision: 1) }</td>
       </tr>
       <tr>
          <td>Total roast time:</td>
          <td>#{@roast_time.nil? ? "-" : @roast_time/1000} (s)</td>
          <td>#{@roast_time.nil? ? "-" : (@roast_time.to_f/1000/60).round(1)} (min)</td>
          <td>&nbsp;</td>
          <td>&nbsp;</td>
          <td>&nbsp;</td>
        </tr>
        <tr>
          <td>Drop temp:</td>
          <td>#{@drop_temp}F</td>
          <td>&nbsp;</td>
          <td>#{@target_drop_temp.nil? ? "-" : @target_drop_temp.to_s + "F" }</td>
          <td>&nbsp;</td>
          <td align=center>#{(@drop_temp.nil? || @target_drop_temp.nil?) ?
                  "-" : number_to_percentage((@drop_temp - @target_drop_temp)*100 / @target_drop_temp, precision: 1) }</td>
        </tr>
     </table>".html_safe
  end

  def update(entry)
    # drying time is the point at which BT hits 287F
    if @dry_time.nil? && entry.BT >= 287
      @dry_time = entry.t
    end

    # time to first crack is the time at which BT hits 400F
    if @FC_time.nil? && entry.BT >= 400
      @FC_time = entry.t
    end

    # Maillard_time is the time from drying time to BT hitting 400F
    if !@dry_time.nil? && !@FC_time.nil?
      @Maillard_time = @FC_time - @dry_time
    end

    # dev time is the time from first crack to drop temp

    # # drop temp is the max temp of BT
    # if @drop_temp.nil? || entry.BT > @drop_temp
    #   @drop_temp = entry.BT
    #   @roast_time = entry.t
    #   @dev_time = (entry.t - @FC_time) if !@FC_time.nil?
    # end

    # drop temp is when heat goes to zero and stays there
    if entry.heat == 0
      if @drop_temp.nil?
        @drop_temp = entry.BT
        @roast_time = entry.t
        @dev_time = (entry.t - @FC_time) if !@FC_time.nil?
      end
    else
      @drop_temp = nil
      @roast_time = nil
      @dev_time = nil
    end
  end
end

class PID
  attr_accessor :Setpoint, :Input, :Error, :Kp, :Ki, :Kd, :P, :I, :D, :Output

  def initialize(input, last_PID, init_i, setpoint, kp, ki, kd)
    @Setpoint = setpoint
    @Input = input
    @Error = @Setpoint - @Input
    @Kp = kp
    @Ki = ki
    @Kd = kd
    @P = @Error * @Kp

    # if this is the first PID, last_PID will be nil, in which case our initial I term is in offset
    iterm = init_i
    iterm = last_PID.I if !last_PID.nil?
    @I = iterm + @Error * @Ki
    @I = 100 if @I > 100
    @I = 0 if @I < 0

    # if this is the first PID, the last input value was zero
    last_input = 0
    @D = 0
    last_input = last_PID.Input if !last_PID.nil?
    @D = (@Input - last_input) * @Kd if !last_PID.nil? && last_input != 0

    # now get our output
    @Output = @P + @I - @D
    @Output = 100 if @Output > 100
    @Output = 0 if @Output < 0
  end
end

class LogEntry
  attr_accessor :t, :offset, :BT, :ET, :BT_ROR_M, :BT_ROR, :ET_ROR, :heat, :fan, :PID

  def initialize
    @BT_ROR = 0
    @ET_ROR = 0
  end

  def get_ROR(lastentry)
    return if lastentry.nil?

    @ET_ROR = (@ET.to_f - lastentry.ET) / (@t - lastentry.t) * 1000
    @BT_ROR = (@BT.to_f - lastentry.BT) / (@t - lastentry.t) * 1000
  end

  def get_PID(last_PID, init_i, setpoint, kp, ki, kd)
    # create the PID data for this entry
    # requires the last PID for the D and I values
    @PID = PID.new(@BT, last_PID, init_i, setpoint, kp, ki, kd)
  end

  def get_data(chart)
    #ET/BT vs ROR
    # "[#{@t.to_i-@offset},#{@ET},#{@BT},#{@BT_ROR_M},#{@BT_ROR},#{@ET_ROR}],"

    # heat/fan vs ROR
    s = "[#{@t.to_i-@offset}"
    s << ",#{@BT}" if chart.show_BT
    s << ",#{@ET}" if chart.show_ET
    s << ",#{@fan}" if chart.show_fan
    s << ",#{@heat}" if chart.show_heat
    if chart.show_PID
      @PID.nil? ? s << ",null" : s << ",#{@PID.P}"
      @PID.nil? ? s << ",null" : s << ",#{@PID.I}"
      @PID.nil? ? s << ",null" : s << ",#{@PID.D}"
      @PID.nil? ? s << ",null" : s << ",#{@PID.Output}"
    end
    @BT_ROR_M.nil? ? s << ",null" : s << ",#{@BT_ROR_M.round(2)}" if chart.show_BT_ROR_M
    s << ",#{@BT_ROR.round(2)}" if chart.show_BT_ROR
    s << ",#{@ET_ROR.round(2)}" if chart.show_ET_ROR
    s << "],\n"
    s
  end

  def self.get_html_header
    "<tr>
         <td>t</td><td>Fan</td><td>Heat</td><td>ET</td><td>BT</td><td>BT_ROR_M</td><td>BT_ROR</td><td>ET_ROR</td>
         <td>P</td><td>I</td><td>D</td><td>PID</td><td>PID-heat</td>
     </tr>"
  end

  def get_html_tr
    # include everything
    bt_ror_m = @BT_ROR_M.nil? ? "-" : @BT_ROR_M.round(2)
    "<tr>
       <td>#{@t.to_i-@offset}</td>
       <td>#{@fan}</td><td>#{@heat}</td>
       <td>#{@ET}</td>
       <td>#{@BT}</td>
       <td>#{bt_ror_m}</td>
       <td>#{@BT_ROR.round(2)}</td>
       <td>#{@ET_ROR.round(2)}</td>
       <td>#{@PID.P.round(0) if !@PID.nil?}</td>
       <td>#{@PID.I.round(0) if !@PID.nil?}</td>
       <td>#{@PID.D.round(0) if !@PID.nil?}</td>
       <td>#{@PID.Output.round(0) if !@PID.nil?}</td>
       <td>#{(@PID.Output - @heat).round(0) if !@PID.nil?}</td>
     </tr>".html_safe
  end
end
