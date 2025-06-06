%% Minicache. Feel free to rename this module and include it in other projects.
%%-----------------------------------------------------------------------------
%% Copyright 2014 Viktor Söderqvist
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

%% @doc A minimalistic time triggered maps based cache data structure.
%%
%% The cache keeps track of when each key was last used. Elements are evicted
%% using manual calls to evict_older_than/2. Most of the functions return a new
%% updated cache object which should be used in subsequent calls.
%%
%% Properties:
%%
%% <ul>
%%   <li>Embeddable in a gen_server or other process</li>
%%   <li>Evicting K elements is O(N + K * log N) which means low overhead when
%%       nothing or few elements are evicted</li>
%% </ul>
%% @private
-module(mysql_cache).

-export_type([cache/2]).
-export([evict_older_than/2, is_empty/1, lookup/2, new/0, size/1, store/3]).

-opaque cache(K, V) :: #{K => {V, integer()}}.

%% @doc Deletes the entries that have not been used for `MaxAge' milliseconds
%% and returns them along with the new state.
-spec evict_older_than(Cache :: cache(K, V), MaxAge :: non_neg_integer()) ->
    {Evicted :: [{K, V}], NewCache :: cache(K, V)}.
evict_older_than(Cache = #{}, MaxAge) ->
    MinTime = timestamp() - MaxAge * 1000,
    {Evicted, Cache1} = maps:fold(
        fun
            (_Key, {_Value, Time}, Acc) when Time >= MinTime ->
                Acc;
	    (Key, {Value, _Time}, {EvictedAcc, CacheAcc}) ->
                {[{Key, Value} | EvictedAcc], maps:remove(Key, CacheAcc)}
        end,
        {[], Cache},
        Cache),
    {Evicted, Cache1}.

%% @doc Looks up a key in a cache. If found, returns the value and a new cache
%% with the 'last used' timestamp updated for the key.
-spec lookup(Key :: K, Cache :: cache(K, V)) ->
    {found, Value :: V, UpdatedCache :: cache(K, V)} | not_found.
lookup(Key, Cache = #{}) ->
    case maps:find(Key, Cache) of
        {ok, {Value, _OldTime}} ->
            Cache1 = Cache#{Key => {Value, timestamp()}},
            {found, Value, Cache1};
        error ->
            not_found
    end.

%% @doc Returns the atom `empty' which represents an empty cache.
-spec new() -> cache(K :: term(), V :: term()).
new() ->
    #{}.

-spec is_empty(cache(K :: term(), V :: term())) -> boolean().
is_empty(Cache = #{}) ->
    Cache =:= #{}.

%% @doc Returns the number of elements in the cache.
-spec size(cache(K :: term(), V :: term())) -> non_neg_integer().
size(Cache = #{}) ->
    maps:size(Cache).

%% @doc Stores a key-value pair in the cache. If the key already exists, the
%% associated value is replaced by `Value'.
-spec store(Key :: K, Value :: V, Cache :: cache(K, V)) -> cache(K, V)
    when K :: term(), V :: term().
store(Key, Value, Cache = #{}) ->
    Cache#{Key => {Value, timestamp()}}.

timestamp() ->
    erlang:monotonic_time(microsecond).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

empty_test() ->
    ?assertEqual(#{}, ?MODULE:new()),
    ?assertEqual(0, ?MODULE:size(#{})),
    ?assertEqual(not_found, ?MODULE:lookup(foo, #{})),
    ?assertMatch({[], #{}}, ?MODULE:evict_older_than(#{}, 10)).

nonempty_test() ->
    Cache = ?MODULE:store(foo, bar, #{}),
    ?assertMatch({found, bar, #{}}, ?MODULE:lookup(foo, Cache)),
    ?assertMatch(not_found, ?MODULE:lookup(baz, Cache)),
    ?assertMatch({[], #{}}, ?MODULE:evict_older_than(Cache, 50)),
    ?assertMatch(#{}, Cache),
    ?assertEqual(1, ?MODULE:size(Cache)),
    receive after 51 -> ok end, %% expire cache
    ?assertEqual({[{foo, bar}], #{}}, ?MODULE:evict_older_than(Cache, 50)),
    %% lookup un-expires cache
    {found, bar, NewCache} = ?MODULE:lookup(foo, Cache),
    ?assertMatch({[], #{}}, ?MODULE:evict_older_than(NewCache, 50)),
    %% store also un-expires
    NewCache2 = ?MODULE:store(foo, baz, Cache),
    ?assertMatch({[], #{}}, ?MODULE:evict_older_than(NewCache2, 50)).

-endif.
