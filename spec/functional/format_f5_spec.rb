require File.dirname(__FILE__) + "/../spec_helper"
require File.dirname(__FILE__) + "/dbf_shared"

describe DBF, "of type f5 (FoxPro with memo file)" do
  before(:each) do
    @table = DBF::Table.new "#{DB_PATH}/dbase_f5.dbf"
  end
  
  it_should_behave_like "DBF"
  
  it "should report the correct version number" do
    @table.version.should == "f5"
  end
  
  it "should have a memo file" do
    @table.should have_memo_file
  end
  
  it "should report the correct memo type" do
    @table.memo_file_format.should == :fpt
  end
  
end