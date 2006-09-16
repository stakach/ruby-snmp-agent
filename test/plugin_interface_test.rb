require File.dirname(__FILE__) + '/test_helper.rb'

require 'snmp/agent'

class SNMP::Agent
	public :get_mib_entry, :get_snmp_value, :next_oid_in_tree
end

class PluginInterfaceTest < Test::Unit::TestCase
	def test_trivial_plugin
		a = SNMP::Agent.new
		
		a.add_plugin('1.2.3') { 42 }
		
		assert_equal(42, a.get_mib_entry('1.2.3'))

		# Special check to make sure that get_mib_entry doesn't
		# mangle the OID passed in
		oid = SNMP::ObjectId.new('1.2.3')
		assert_equal(42, a.get_mib_entry(oid))
		assert_equal(SNMP::ObjectId, oid.class)
		assert_equal('1.2.3', oid.to_s)
	end

	def test_almost_as_trivial_plugin
		a = SNMP::Agent.new
		
		a.add_plugin('1.2.3') { [42] }
		
		assert_equal({0=>42}, a.get_mib_entry('1.2.3'))
		assert_equal(SNMP::NoSuchObject, a.get_snmp_value('1.2.3').class)
		assert_equal(42, a.get_mib_entry('1.2.3.0'))
	end

	def test_a_set_of_data
		a = SNMP::Agent.new
		
		a.add_plugin('1.2.3') { [0, 1, 2, 3, 4, 5] }
		
		assert_equal({0=>0,1=>1,2=>2,3=>3,4=>4,5=>5}, a.get_mib_entry('1.2.3'))
		assert_equal(SNMP::NoSuchObject, a.get_snmp_value('1.2.3').class)
		6.times { |v| assert_equal(v, a.get_mib_entry("1.2.3.#{v}")) }
	end

	def test_multiple_plugins
		a = SNMP::Agent.new
		
		a.add_plugin('1.1') { [nil, %w{the quick brown etc}] }
		a.add_plugin('1.2.3') { [0, 1, 2] }
		a.add_plugin('4.5.6') { [5, 6, 7] }

		assert_equal({0 => nil, 1 => {0=>'the', 1=>'quick', 2=>'brown', 3=>'etc'}},
		             a.get_mib_entry('1.1'))
		assert_equal(nil, a.get_mib_entry('1.1.0'))
		assert_equal('brown', a.get_mib_entry('1.1.1.2'))
		assert_equal({0=>0, 1=>1, 2=>2}, a.get_mib_entry('1.2.3'))
		assert_equal(0, a.get_mib_entry('1.2.3.0'))
		assert_equal({0=>5, 1=>6, 2=>7}, a.get_mib_entry('4.5.6'))
		assert_equal(6, a.get_mib_entry('4.5.6.1'))
	end

	def test_plugins_must_be_leaf_nodes
		a = SNMP::Agent.new
		
		# OK, since the tree is empty
		assert_nothing_raised { a.add_plugin('1.2.3') { 42 } }
		
		# OK, since it's in a separate top-level branch
		assert_nothing_raised { a.add_plugin('2.3.4') { [5, 6, 7] } }
		
		# OK, since it's coming off an adjacent node
		assert_nothing_raised { a.add_plugin('2.3.5') { [8, 13, 21] } }
		
		# Not OK, since we'd overwrite an existing subtree
		assert_raise(ArgumentError) { a.add_plugin('1') { "muahahahaha!" } }

		# Not OK, since it would attach itself somewhere inside an
		# existing plugin's "namespace"
		assert_raise(ArgumentError) { a.add_plugin('1.2.3.4') { "help me!" } }
	end

	def test_a_tree_of_data
		a = SNMP::Agent.new
		
		a.add_plugin('1.2.3') { [[11, 12, 13], [21, 22, 23], [31, 32, 33]] }

		assert_equal({0=>{0=>11, 1=>12, 2=>13}, 1=>{0=>21, 1=>22, 2=>23}, 2=>{0=>31, 1=>32, 2=>33}},
		             a.get_mib_entry('1.2.3'))
		assert_equal(SNMP::NoSuchObject, a.get_snmp_value('1.2.3').class)
		assert_equal({0=>11, 1=>12, 2=>13}, a.get_mib_entry('1.2.3.0'))
		assert_equal(SNMP::NoSuchObject, a.get_snmp_value('1.2.3.0').class)
		
		3.times { |i|
			3.times { |j|
				assert_equal("#{i+1}#{j+1}".to_i, a.get_mib_entry("1.2.3.#{i}.#{j}"))
			}
		}
	end

	def test_a_bridge_too_far
		a = SNMP::Agent.new
		
		a.add_plugin('1.2.3') { [0, 1, 2] }
		
		# Fails because we don't have .1.2.3.4
		assert_equal(nil, a.get_mib_entry('1.2.3.4'))
		assert_equal(SNMP::NoSuchObject, a.get_snmp_value('1.2.3.4').class)
		
		# Fails because we don't have a subtree from .1.2.3.1
		assert_equal(nil, a.get_mib_entry('1.2.3.1.0'))
		assert_equal(SNMP::NoSuchObject, a.get_snmp_value('1.2.3.1.0').class)
	end

	def test_next_oid_in_tree
		a = SNMP::Agent.new
		
		a.add_plugin('1.1') { [nil, %w{the quick brown etc}] }
		a.add_plugin('1.2.3') { [0, 1, 2] }
		a.add_plugin('4.5.6') { [5, 6, 7] }

		# Simple case -- delve into the tree in the same plugin
		assert_equal('1.2.3.0', a.next_oid_in_tree('1.2.3').to_s)
		
		# Slightly harder -- find the first real value in the next tree
		assert_equal('1.2.3.0', a.next_oid_in_tree('1.2').to_s)
		
		# Find when between jobs
		assert_equal('4.5.6.0', a.next_oid_in_tree('2.3.4.5.6.78').to_s)
		
		# What about when we're off the end of the tree?
		assert_equal(SNMP::EndOfMibView, a.next_oid_in_tree('5').class)
		
		# Or even *at* the end of the tree
		assert_equal(SNMP::EndOfMibView, a.next_oid_in_tree('4.5.6.2').class)

		a = SNMP::Agent.new
		
		a.add_plugin('1.2.3') { [1, 1, 2, 3, 5, 8, 13] }
		
		assert_equal(5, a.get_mib_entry('1.2.3.4'))
		assert_equal('1.2.3.5', a.next_oid_in_tree('1.2.3.4').to_s)

	end
end