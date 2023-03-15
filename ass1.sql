-- COMP3311 23T1 Assignment 1

-- Q1: amount of alcohol in the best beers

-- put any Q1 helper views/functions here

create or replace view Q1(beer, "sold in", alcohol)
as 
select      name,
            volume||'ml '||sold_in,
            (ABV*volume/100)::numeric(4,1)||'ml'
from        beers
where       rating > 9;

-- Q2: beers that don't fit the ABV style guidelines

-- put any Q2 helper views/functions here

create or replace view Q2(beer, style, abv, reason)
as
select      b.name, s.name,b.abv,
case
    when abv < min_abv then 'too weak by '||(min_abv-ABV)::numeric(4,1)||'%'
    when abv > max_abv then 'too strong by '||(ABV-max_abv)::numeric(4,1)||'%'
end
from        beers b
join        styles s
on          b.style = s.id
where       abv < min_abv or abv > max_abv;

-- Q3: Number of beers brewed in each country

-- put any Q3 helper views/functions here

create or replace view Q3(country, "#beers")
as
select            c.name, count(b.id)
from              beers b
right join        brewed_by on b.id = brewed_by.beer
right join        breweries on brewed_by.brewery=breweries.id
right join        locations l on breweries.located_in = l.id 
right join        countries c on l.within = c.id
group by          c.name
order by          c.name;

-- Q4: Countries where the worst beers are brewed

-- put any Q4 helper views/functions here

create or replace view Q4(beer, brewery, country)
as
select      b.name, breweries.name, c.name
from        beers b
join        brewed_by on b.id = brewed_by.beer
join        breweries on brewed_by.brewery=breweries.id
join        locations l on breweries.located_in = l.id 
join        countries c on l.within = c.id
where       b.rating < 3;

-- Q5: Beers that use ingredients from the Czech Republic

-- put any Q5 helper views/functions here

create or replace view Q5(beer, ingredient, "type")
as
select      b.name, i.name, i.itype
from        beers b 
join        contains on contains.beer = b.id
join        ingredients i on contains.ingredient = i.id
join        countries c on i.origin = c.id
where       c.name =  'Czech Republic';
-- Q6: Beers containing the most used hop and the most used grain

-- put any Q6 helper views/functions here

create or replace view pop_hop(hop_id, hop_use) as 
select      i.id, count(c.ingredient)
from        ingredients i
join        contains c on c.ingredient = i.id
where       i.itype = 'hop'
group by    i.id
order by    count(c.ingredient) desc; 

create or replace view pop_grain(grain_id, grain_use) as 
select      i.id, count(c.ingredient)
from        ingredients i
join        contains c on c.ingredient = i.id
where       i.itype = 'grain'
group by    i.id
order by    count(c.ingredient) desc; 

create or replace view pop_ingredient_beers(beer_id) as
select      c.beer
from        contains c
where       c.ingredient = (select hop_id from pop_hop where hop_use = 
                                (select max(hop_use) from pop_hop))
intersect
select      c.beer
from        contains c
where       c.ingredient = (select grain_id from pop_grain where grain_use = 
                                (select max(grain_use) from pop_grain));

create or replace view Q6(beer)
as
select      name
from        beers
where       id 
in          (select * from pop_ingredient_beers);



-- Q7: Breweries that make no beer

-- put any Q7 helper views/functions here

create or replace view breweries_beer_count(brewer_name, beer_count) as
select            breweries.name, count(b.id)
from              beers b
right join        brewed_by on b.id = brewed_by.beer
right join        breweries on brewed_by.brewery=breweries.id
group by          breweries.name;

create or replace view Q7(brewery)
as
select            brewer_name
from              breweries_beer_count
where             beer_count = 0;

-- Q8: Function to give "full name" of beer

-- put any Q8 helper views/functions here

create or replace view beer_and_brewery as
select 
    b.id as beer_id,
    b.name as beer_name, 
    breweries.id as brewery_id,
    breweries.name as brewery_name 
from beers b
join brewed_by on b.id = brewed_by.beer
join breweries on brewed_by.brewery = breweries.id;

create or replace function
	Q8(beer_id integer) returns text
as $$
declare
response    text;
tup         beer_and_brewery;
_brewer_name text;
temp_brewname text;
_beer_name   text;
begin
    for tup in
    select * from beer_and_brewery b
    where b.beer_id = q8.beer_id
    loop
        temp_brewname = REGEXP_REPLACE(tup.brewery_name,' (Beer|Brew).*$', '');
        if (temp_brewname = '') then
            temp_brewname = tup.brewery_name;
        end if;
        if (_brewer_name is null) then
            _beer_name = tup.beer_name;
            _brewer_name = temp_brewname;
        else
            _brewer_name = concat(_brewer_name ,' + ',temp_brewname);
        end if;
    end loop;
    if (_beer_name is null) then
        response = 'No such beer';
    else
        response = concat(_brewer_name,' ',_beer_name);
    end if;
    return response;
end;
$$ language plpgsql;

-- Q9: Beer data based on partial match of beer name

drop type if exists BeerData cascade;
create type BeerData as (beer text, brewer text, info text);


-- put any Q9 helper views/functions here

create or replace view beer_brewery_ingredients as
select 
    beer_id, beer_name, brewery_id, brewery_name,
    i.itype as ingredient_type,
    i.name as ingredient_name
from beer_and_brewery b
left join contains c on c.beer = b.beer_id
left join ingredients i on i.id = c.ingredient;

create or replace function concat_info(hopinfo text, graininfo text, extrasinfo text) returns text
as $$
declare
allinfo text := '';
begin
    if  hopinfo <> '' and (graininfo <> '' or extrasinfo <> '') then
        allinfo = concat(allinfo, hopinfo, e'\n');
    else
        allinfo = concat(allinfo, hopinfo);
    end if;

    if  graininfo <> '' and extrasinfo <> '' then
        allinfo = concat(allinfo, graininfo, e'\n');
    else
        allinfo = concat(allinfo, graininfo);
    end if;
    allinfo = concat(allinfo, extrasinfo);
    return allinfo;
end;
$$ language plpgsql;

create or replace function
	Q9(partial_name text) returns setof BeerData
as $$
declare
rec                 beer_brewery_ingredients;
prev_rec            beer_brewery_ingredients;
tup                 BeerData    := ('','','');
hopinfo             text := '';
graininfo           text := '';
extrasinfo          text := '';
begin
    for rec in
    select * from beer_brewery_ingredients b
    where b.beer_name ~* partial_name
    order by beer_id, ingredient_name
    loop

        if(tup.beer = '') then
            tup     := (rec.beer_name,rec.brewery_name,'');
            prev_rec := rec;
        end if;
        if (prev_rec.beer_id = rec.beer_id and prev_rec.brewery_name <> rec.brewery_name) then
            tup.brewer = concat(tup.brewer, ' + ', rec.brewery_name);
        elsif (prev_rec.beer_id <> rec.beer_id) then 
            tup.info = concat_info(hopinfo,graininfo,extrasinfo);
            return next tup;
            tup     := (rec.beer_name,rec.brewery_name,'');
            hopinfo := '';
            graininfo := '';
            extrasinfo := '';
        end if;
        case
            when rec.ingredient_type = 'hop' and hopinfo = '' then 
                hopinfo     = concat('Hops: ',rec.ingredient_name);
            when rec.ingredient_type = 'hop' then 
                hopinfo     = concat(hopinfo, ',',rec.ingredient_name);
            when rec.ingredient_type = 'grain' and graininfo = '' then 
                graininfo   = concat('Grain: ', rec.ingredient_name);
            when rec.ingredient_type = 'grain' then 
                graininfo   = concat(graininfo, ',',rec.ingredient_name);    
            when rec.ingredient_type = 'adjunct' and extrasinfo = '' then 
                extrasinfo  = concat('Extras: ', rec.ingredient_name);
            when rec.ingredient_type = 'adjunct' then 
                extrasinfo  = concat(extrasinfo, ',',rec.ingredient_name);
            else
        end case;
        prev_rec := rec;
    end loop;
    if (tup.beer <> '') then
        tup.info = concat_info(hopinfo,graininfo,extrasinfo);
        return next tup;
    end if;
end;
$$ language plpgsql;

