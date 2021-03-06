# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/measures/measure_writing_guide/

require 'csv'

# start the measure
class BuildExistingModelEnergyPlus < OpenStudio::Ruleset::WorkspaceUserScript

  # human readable name
  def name
    return "Build Existing Model EnergyPlus"
  end

  # human readable description
  def description
    return "For EnergyPlus measures, builds the OpenStudio Model for an existing building."
  end

  # human readable description of modeling approach
  def modeler_description
    return "For EnergyPlus measures, builds the OpenStudio Model using the sampling csv file, which contains the specified parameters for each existing building. Based on the supplied building number, those parameters are used to run the OpenStudio measures with appropriate arguments and build up the OpenStudio model."
  end

  # define the arguments that the user will input
  def arguments(workspace)
    args = OpenStudio::Ruleset::OSArgumentVector.new

    always_run = OpenStudio::Ruleset::OSArgument.makeIntegerArgument("always_run", true)
    always_run.setDisplayName("Always Run")
    args << always_run
    
    return args
  end

  # define what happens when the measure is run
  def run(workspace, runner, user_arguments)
    super(workspace, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(workspace), user_arguments)
      return false
    end
    
    always_run = runner.getIntegerArgumentValue("always_run",user_arguments)
    
    # Get file/dir paths
    resources_dir = File.absolute_path(File.join(File.dirname(__FILE__), "..", "..", "lib", "resources")) # Should have been uploaded per 'Other Library Files' in analysis spreadsheet
    helper_methods_file = File.join(resources_dir, "helper_methods.rb")
    measures_dir = File.join(resources_dir, "measures")
    lookup_file = File.join(resources_dir, "options_lookup.tsv")
    resstock_csv = File.absolute_path(File.join(File.dirname(__FILE__), "..", "..", "lib", "worker_initialize", "resstock.csv")) # Should have been generated by the Worker Initialization Script (run_sampling.rb)
    
    # Load helper_methods
    require File.join(File.dirname(helper_methods_file), File.basename(helper_methods_file, File.extname(helper_methods_file)))

    # Check file/dir paths exist
    check_dir_exists(measures_dir, runner)
    check_file_exists(lookup_file, runner)
    check_file_exists(resstock_csv, runner)
    
    building_id = get_value_from_runner_past_results("building_id", runner).to_i

    # Retrieve all data associated with sample number
    building_col_name = "Building"
    bldg_data = get_data_for_sample(resstock_csv, building_id, runner, building_col_name)
    
    # Retrieve order of parameters to run
    parameters_ordered = get_parameters_ordered(resstock_csv)

    # Obtain measures and arguments to be called
    measures = {}
    parameters_ordered.each do |parameter_name|
        next if parameter_name == building_col_name
    
        # Get measure name and arguments associated with the option
        option_name = bldg_data[parameter_name]
        print_option_assignment(parameter_name, option_name, runner)
        register_value(runner, parameter_name, option_name)

        get_measure_args_from_option_name(lookup_file, option_name, parameter_name, runner).each do |measure_subdir, args_hash|
            if not measures.has_key?(measure_subdir)
                measures[measure_subdir] = {}
            end
            # Append args_hash to measures[measure_subdir]
            args_hash.each do |k, v|
                measures[measure_subdir][k] = v
            end
        end

    end
    
    # Call each measure for sample to build up model
    measures.keys.each do |measure_subdir|
        next if measure_subdir != "ResidentialAirflowOriginalModel" # Temporary while Airflow is an EnergyPlus measure
        # Gather measure arguments and call measure
        full_measure_path = File.join(measures_dir, measure_subdir, "measure.rb")
        check_file_exists(full_measure_path, runner)
        
        measure_instance = get_measure_instance(full_measure_path)
        argument_map = get_argument_map(workspace, measure_instance, measures[measure_subdir], lookup_file, measure_subdir, runner)
        print_measure_call(measures[measure_subdir], measure_subdir, runner)

        if not run_measure(workspace, measure_instance, argument_map, runner)
            return false
        end
    end

    return true

  end
  
  def get_data_for_sample(resstock_csv, building_id, runner, building_col_name)
    CSV.foreach(resstock_csv, headers:true) do |sample|
        next if sample[building_col_name].to_i != building_id
        return sample
    end
    # If we got this far, couldn't find the sample #
    msg = "Could not find row for #{building_id.to_s} in #{File.basename(resstock_csv).to_s}."
    runner.registerError(msg)
    fail msg
  end
  
  def get_parameters_ordered(resstock_csv)
    return CSV.open(resstock_csv, 'r') { |csv| csv.first }
  end
  
end

# register the measure to be used by the application
BuildExistingModelEnergyPlus.new.registerWithApplication
