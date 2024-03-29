/****** Object:  StoredProcedure [dbo].[sp_CreateProcedure]    Script Date: 02-06-2019 20:36:10 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER procedure [dbo].[sp_CreateProcedure]
	@TableName			varchar(300) = ''
AS
BEGIN
	declare 
		@ProcedureName			varchar(500),
		@PrimaryColumnName		varchar(500),
		@ColumnName				varchar(500),
		@ColumnType				varchar(100),
		@IsLengthField			bit,
		@LengthValue			varchar(100),
		@Precision				varchar(10),
		@Scale					varchar(10),
		@IsNullField			bit,
		@IsPrimaryKey			bit,
		@IsIdentity				bit,
		@ColumnCount			int = 0,
		@count					int = 1,
		@dropsqlstring			varchar(max) = '',
		@sqlstring				varchar(max) = '',
		@insertstring1			varchar(max) = '',
		@updatestring1			varchar(max) = '',
		@insertstring2			varchar(max) = '',
		@insertnotnullquery		varchar(max) = '',
		@updatenotnullquery		varchar(max) = '',
		@updatewherestring		varchar(max) = '',
		@normalizedcolumnname	varchar(500) = '',
		@dynamicquerystring		varchar(max) = ''

	IF(@TableName in (select isnull(TableName,'') from [st_tbl_ExcludeAutoGeneration]))
	BEGIN
		SELECT 'Procedure Already Standardized'
		GOTO LBL1
	END

	IF(ISNULL(@TableName,'') <> '')
	BEGIN
		IF(OBJECT_ID('tempdb..#tmp_Columns') IS NOT NULL)
			drop table #tmp_Columns

		create table #tmp_Columns(ColumnName varchar(500),ColumnType varchar(100),LengthValue varchar(100),Precision varchar(10),Scale varchar(10), IsNullField bit, IsPrimaryKey bit,IsIdentity bit)

		insert into #tmp_Columns select col.name,t.name,col.max_length,col.precision,col.scale,col.is_nullable,pk.column_id,col.is_identity
			from sys.tables as tab
				left join sys.columns as col
					on tab.object_id = col.object_id
				left join sys.types as t
					on col.user_type_id = t.user_type_id
				left join sys.default_constraints as def
					on def.object_id = col.default_object_id
				left join (
						select index_columns.object_id, 
								index_columns.column_id
						from sys.index_columns
								inner join sys.indexes 
									on index_columns.object_id = indexes.object_id
								and index_columns.index_id = indexes.index_id
						where indexes.is_primary_key = 1
						) as pk 
				on col.object_id = pk.object_id and col.column_id = pk.column_id
			where tab.name = @TableName

		select @ColumnCount = count(*) from #tmp_Columns

		select @ProcedureName = 'po_'+substring(@TableName,5,LEN(@TableName))

		select @dropsqlstring = @dropsqlstring + 'IF(OBJECT_ID('''+@ProcedureName+''') IS NOT NULL)'									+ CHAR(13)
		select @dropsqlstring = @dropsqlstring + '	drop procedure '+@ProcedureName														+ CHAR(13)

		select @sqlstring = @sqlstring +  'CREATE PROCEDURE [dbo].['  + @ProcedureName + ']'											+ CHAR(13)
	
		select @insertstring1 = @insertstring1 + '		INSERT '+@TableName+'('															+ CHAR(13)
		select @insertstring2 = @insertstring2 + '		VALUES ('																		+ CHAR(13)
		select @updatestring1 = @updatestring1 + '		UPDATE '+@TableName																+ CHAR(13)
		select @updatestring1 = @updatestring1 + '		SET '																			+ CHAR(13)

		declare c1 cursor for select * from #tmp_Columns
		open c1
		fetch c1 into 	
			@ColumnName,
			@ColumnType,
			@LengthValue,
			@Precision,
			@Scale,
			@IsNullField,
			@IsPrimaryKey,
			@IsIdentity
		while(@@FETCH_STATUS=0)
		begin
			select @sqlstring = @sqlstring + '	@'+ @ColumnName 

			if(@ColumnType in ('int','tinyint','bigint','decimal','bit','float'))
			begin
				select @dynamicquerystring = @dynamicquerystring + '			IF(ISNULL(@'+@ColumnName+',0) > 0)'						+ CHAR(13)
				select @dynamicquerystring = @dynamicquerystring + '				select @sqlstring = @sqlstring + ''			and '+@ColumnName+' = ''+ Convert(nvarchar,@'+@ColumnName +') +'''''+ CHAR(13)
			end
			else if(@ColumnType in ('varchar','char','nvarchar'))
			begin
				select @dynamicquerystring = @dynamicquerystring + '			IF(ISNULL(@'+@ColumnName+','''') != '''')'				+ CHAR(13)
				select @dynamicquerystring = @dynamicquerystring + '				select @sqlstring = @sqlstring + ''			and '+@ColumnName+'  = ''''''+ @'+@ColumnName  +'+'''''''''+ CHAR(13)
			end
			else if(@ColumnType in ('datetime','date'))
			begin
				select @dynamicquerystring = @dynamicquerystring + '			IF(ISNULL(@'+@ColumnName+','''') != '''')'				+ CHAR(13)
				select @dynamicquerystring = @dynamicquerystring + '				select @sqlstring = @sqlstring + ''			and '+@ColumnName+'  = ''''''+ Convert(nvarchar,@'+@ColumnName +') +'''''''''+ CHAR(13)
			end

			if(@ColumnType in ('int','tinyint','bigint','datetime','date','bit','float'))
			begin
				select @sqlstring = @sqlstring + CHAR(9)+ CHAR(9) + CHAR(9)+ CHAR(9)  + @ColumnType + ','								+ CHAR(13)
			end
			else if(@ColumnType in ('nvarchar'))
			begin
				if(@LengthValue = '8000')
					select @sqlstring = @sqlstring + CHAR(9)+ CHAR(9) + CHAR(9) + CHAR(9) + @ColumnType + '(4000),'						+ CHAR(13)
				else
					select @sqlstring = @sqlstring + CHAR(9)+ CHAR(9) + CHAR(9)+ CHAR(9)  + @ColumnType + '(' + @LengthValue+ '),'		+ CHAR(13)
			end
			else if(@ColumnType in ('varchar','char'))
			begin
				if(@LengthValue = '-1')
					select @sqlstring = @sqlstring + CHAR(9)+ CHAR(9) + CHAR(9) + CHAR(9) + @ColumnType + '(MAX),'						+ CHAR(13)
				else
					select @sqlstring = @sqlstring + CHAR(9)+ CHAR(9) + CHAR(9)+ CHAR(9)  + @ColumnType + '(' + @LengthValue+ '),'		+ CHAR(13)
			end
			else if (@ColumnType in ('varbinary' , 'timestamp'))
			begin
				if(@LengthValue = '-1' OR @ColumnType = 'timestamp')
					select @sqlstring = @sqlstring + CHAR(9)+ CHAR(9) + CHAR(9) + CHAR(9) + 'nvarchar' + '(MAX),'						+ CHAR(13)
				else
					select @sqlstring = @sqlstring + CHAR(9)+ CHAR(9) + CHAR(9) + CHAR(9) + 'nvarchar' + '(' + @LengthValue+ '),'		+ CHAR(13)
			end
			else if (@ColumnType in ('decimal'))
			begin
				select @sqlstring = @sqlstring + CHAR(9)+ CHAR(9) + CHAR(9)  + CHAR(9)+ @ColumnType + '('+@Precision + ','+ @Scale +'),'+ CHAR(13)
			end

			if(isnull(@IsPrimaryKey,0)<>1)
			begin
				if(@count <> @ColumnCount)
				begin
					IF(@ColumnType != 'timestamp')
					begin
						select @insertstring1 = @insertstring1 + '			'+@ColumnName+','												+ CHAR(13)
						IF(@ColumnType = 'varbinary')
						begin
							select @insertstring2 = @insertstring2 + '			Convert(varbinary(max),@'+@ColumnName+'),'					+ CHAR(13)
							IF(isnull(@IsIdentity,0) = 0)
								select @updatestring1 = @updatestring1 + '			'+@ColumnName +'					= Convert(varbinary(max),@'+@ColumnName+'),'	+ CHAR(13)
						end
						else
						begin
							select @insertstring2 = @insertstring2 + '			@'+@ColumnName+','											+ CHAR(13)
							IF(isnull(@IsIdentity,0) = 0)
								select @updatestring1 = @updatestring1 + '			'+@ColumnName +'					= @'+@ColumnName+','+ CHAR(13)
						end
					end
				end
				else
				begin
					IF(@ColumnType != 'timestamp')
					begin
						select @insertstring1 = @insertstring1 + '			'+@ColumnName +')'												+ CHAR(13)
						IF(@ColumnType = 'varbinary')
						begin
							select @insertstring2 = @insertstring2 + '			Convert(varbinary(max),@'+@ColumnName +'))'					+ CHAR(13)
							IF(isnull(@IsIdentity,0) = 0)
								select @updatestring1 = @updatestring1 + '			'+@ColumnName +'					= Convert(varbinary(max),@'+@ColumnName	+')'	+ CHAR(13)
						end
						else
						begin
							select @insertstring2 = @insertstring2 + '			@'+@ColumnName +')'											+ CHAR(13)
							IF(isnull(@IsIdentity,0) = 0)
								select @updatestring1 = @updatestring1 + '			'+@ColumnName +'					= @'+@ColumnName	+ CHAR(13)
						end
					end
					else
					begin
						select @insertstring1 = SUBSTRING(@insertstring1,0,LEN(@insertstring1)-1)											+ CHAR(13)
						select @insertstring2 = SUBSTRING(@insertstring2,0,LEN(@insertstring2)-1)											+ CHAR(13)
						select @updatestring1 = SUBSTRING(@updatestring1,0,LEN(@updatestring1)-1)											+ CHAR(13)
						select @insertstring1 = @insertstring1 + '		)'																	+ CHAR(13)
						select @insertstring2 = @insertstring2 + '		)'																	+ CHAR(13)	
					end
				end
			end
			--Not null validation
			if(isnull(@IsNullField,1) =0)
			begin

				select @normalizedcolumnname =  replace(@ColumnName,'txt_','')
				select @normalizedcolumnname =  replace(@normalizedcolumnname,'int_','')
				select @normalizedcolumnname =  replace(@normalizedcolumnname,'chr_','')
				select @normalizedcolumnname =  replace(@normalizedcolumnname,'dte_','')
				select @normalizedcolumnname =  replace(@normalizedcolumnname,'rwv_','')
				select @normalizedcolumnname =  replace(@normalizedcolumnname,'is_','')
				select @normalizedcolumnname =  replace(@normalizedcolumnname,'hsh_','')
				select @normalizedcolumnname =  replace(@normalizedcolumnname,'enc_','')
				select @normalizedcolumnname =  replace(@normalizedcolumnname,'bit_','')
				select @normalizedcolumnname =  replace(@normalizedcolumnname,'vrb_','')
				select @normalizedcolumnname =  replace(@normalizedcolumnname,'flt_','')
				select @normalizedcolumnname =  replace(@normalizedcolumnname,'dcm_','')
				select @normalizedcolumnname =  replace(@normalizedcolumnname,'_',' ')

				IF(@ColumnType != 'timestamp')
				begin
					if(ISNULL(@IsIdentity,0) =0)
					begin
						if(@ColumnType in ('varchar','char','nvarchar'))
						begin					
							select @insertnotnullquery = @insertnotnullquery + '		IF(ISNULL(@' + @ColumnName + ','''')='''')'		+ CHAR(13)
							select @insertnotnullquery = @insertnotnullquery + '		BEGIN'											+ CHAR(13)
							select @insertnotnullquery = @insertnotnullquery + '			SELECT @error_Code = 3001'						+ CHAR(13)
							select @insertnotnullquery = @insertnotnullquery + '			SELECT @msg = '''+@normalizedcolumnname+ ' Cannot Be Empty'''		+ CHAR(13)
							select @insertnotnullquery = @insertnotnullquery + '			GOTO LBL1'									+ CHAR(13)
							select @insertnotnullquery = @insertnotnullquery + '		END'											+ CHAR(13)
						end
						else
						begin
							select @insertnotnullquery = @insertnotnullquery + '		IF(@' + @ColumnName + ' IS NULL)'				+ CHAR(13)
							select @insertnotnullquery = @insertnotnullquery + '		BEGIN'											+ CHAR(13)
							select @insertnotnullquery = @insertnotnullquery + '			SELECT @error_Code = 3001'						+ CHAR(13)
							select @insertnotnullquery = @insertnotnullquery + '			SELECT @msg = '''+@normalizedcolumnname+ ' Cannot Be Empty'''		+ CHAR(13)
							select @insertnotnullquery = @insertnotnullquery + '			GOTO LBL1'									+ CHAR(13)
							select @insertnotnullquery = @insertnotnullquery + '		END'											+ CHAR(13)
						end
					end
				end

				if(@ColumnType in ('varchar','char','nvarchar'))
				begin					
					select @updatenotnullquery = @updatenotnullquery + '		IF(ISNULL(@' + @ColumnName + ','''')='''')'				+ CHAR(13)
					select @updatenotnullquery = @updatenotnullquery + '		BEGIN'													+ CHAR(13)
					select @updatenotnullquery = @updatenotnullquery + '			SELECT @error_Code = 3001'								+ CHAR(13)
					select @updatenotnullquery = @updatenotnullquery + '			SELECT @msg = '''+@normalizedcolumnname+ ' Cannot Be Empty'''				+ CHAR(13)
					select @updatenotnullquery = @updatenotnullquery + '			GOTO LBL1'											+ CHAR(13)
					select @updatenotnullquery = @updatenotnullquery + '		END'													+ CHAR(13)
				end
				else
				begin
					select @updatenotnullquery = @updatenotnullquery + '		IF(@' + @ColumnName + ' IS NULL)'						+ CHAR(13)
					select @updatenotnullquery = @updatenotnullquery + '		BEGIN'													+ CHAR(13)
					select @updatenotnullquery = @updatenotnullquery + '			SELECT @error_Code = 3001'								+ CHAR(13)
					select @updatenotnullquery = @updatenotnullquery + '			SELECT @msg = '''+@normalizedcolumnname+ ' Cannot Be Empty'''	+ CHAR(13)
					select @updatenotnullquery = @updatenotnullquery + '			GOTO LBL1'											+ CHAR(13)
					select @updatenotnullquery = @updatenotnullquery + '		END'													+ CHAR(13)
				end
			end

			IF(@ColumnType = 'timestamp')
			begin
				select @updatewherestring = @updatewherestring + '			AND ((['+@ColumnName+'] = Convert(Timestamp,@'+@ColumnName+')) OR '+ CHAR(13)
				select @updatewherestring = @updatewherestring + '			(['+@ColumnName+'] IS NULL AND @'+@ColumnName+' IS NULL))'	+ CHAR(13)
			end

			select @count = @count + 1
			fetch c1 into 	
				@ColumnName,
				@ColumnType,
				@LengthValue,
				@Precision,
				@Scale,
				@IsNullField,
				@IsPrimaryKey,
				@IsIdentity
		end
		close c1
		deallocate c1

		select @sqlstring = @sqlstring + '	@ind							varchar(2),'												+ CHAR(13)
		select @sqlstring = @sqlstring + '	@ind1							varchar(2),'												+ CHAR(13)
		select @sqlstring = @sqlstring + '	@msg							varchar(500) output,'										+ CHAR(13)
		select @sqlstring = @sqlstring + '	@error_Code						int output,'												+ CHAR(13)
		select @sqlstring = @sqlstring + '	@new_Id							int output'													+ CHAR(13)
		select @sqlstring = @sqlstring + 'AS'																							+ CHAR(13)
		select @sqlstring = @sqlstring + 'BEGIN'																						+ CHAR(13)
		select @sqlstring = @sqlstring + '	DECLARE @rowcnt int'																		+ CHAR(13)
		select @sqlstring = @sqlstring + '	DECLARE @sqlstring varchar(max) = '''''														+ CHAR(13)
		select @sqlstring = @sqlstring + '	IF(@ind =''1'')'																			+ CHAR(13)
		select @sqlstring = @sqlstring + '	BEGIN'																						+ CHAR(13)
		select @sqlstring = @sqlstring + '		IF(@ind1 = ''1'')'																		+ CHAR(13)
		select @sqlstring = @sqlstring + '		BEGIN'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '			select @sqlstring = @sqlstring + ''	select * ''			+ CHAR(13)'					+ CHAR(13)
		select @sqlstring = @sqlstring + '			select @sqlstring = @sqlstring + ''		from''			+ CHAR(13)'					+ CHAR(13)
		select @sqlstring = @sqlstring + '			select @sqlstring = @sqlstring + ''			' + @TableName + '''	+ CHAR(13)'		+ CHAR(13)
		select @sqlstring = @sqlstring + '			select @sqlstring = @sqlstring + ''		where''			+ CHAR(13)'					+ CHAR(13)
		select @sqlstring = @sqlstring + '			select @sqlstring = @sqlstring + ''			1 = 1''		+ CHAR(13)'					+ CHAR(13)
		select @sqlstring = @sqlstring + @dynamicquerystring																			+ CHAR(13)
		select @sqlstring = @sqlstring + '			print(@sqlstring)'																	+ CHAR(13)
		select @sqlstring = @sqlstring + '			exec(@sqlstring)'																	+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @rowcnt = @@ROWCOUNT'														+ CHAR(13)
		select @sqlstring = @sqlstring + '			IF(@rowcnt=0)'																		+ CHAR(13)
		select @sqlstring = @sqlstring + '			BEGIN'																				+ CHAR(13)
		select @sqlstring = @sqlstring + '				SELECT @error_Code = 3002'														+ CHAR(13)
		select @sqlstring = @sqlstring + '				SELECT @msg = ''No Records Found'''												+ CHAR(13)
		select @sqlstring = @sqlstring + '				GOTO LBL1'																		+ CHAR(13)
		select @sqlstring = @sqlstring + '			END'																				+ CHAR(13)
		select @sqlstring = @sqlstring + '			ELSE'																				+ CHAR(13)
		select @sqlstring = @sqlstring + '			BEGIN'																				+ CHAR(13)
		select @sqlstring = @sqlstring + '				SELECT @error_Code = 3003'														+ CHAR(13)
		select @sqlstring = @sqlstring + '				SELECT @msg = ''Success '' + Convert(varchar,@rowcnt) + '' Records Found'''		+ CHAR(13)
		select @sqlstring = @sqlstring + '				GOTO LBL3'																		+ CHAR(13)
		select @sqlstring = @sqlstring + '			END'																				+ CHAR(13)
		select @sqlstring = @sqlstring + '		END'																					+ CHAR(13)
		select @PrimaryColumnName = ColumnName from #tmp_Columns where IsPrimaryKey = 1
		IF(ISNULL(@PrimaryColumnName,'')<>'')
		begin
			select @sqlstring = @sqlstring + '		ELSE IF(ISNULL(@'+@PrimaryColumnName+',0) > 0)'										+ CHAR(13)
			select @sqlstring = @sqlstring + '		BEGIN'																				+ CHAR(13)
			select @sqlstring = @sqlstring + '			SELECT * FROM '+@TableName+' WHERE '+@PrimaryColumnName+' = @'+@PrimaryColumnName+''	+ CHAR(13)
			select @sqlstring = @sqlstring + '			SELECT @rowcnt = @@ROWCOUNT'													+ CHAR(13)
			select @sqlstring = @sqlstring + '			IF(@rowcnt=0)'																	+ CHAR(13)
			select @sqlstring = @sqlstring + '			BEGIN'																			+ CHAR(13)
			select @sqlstring = @sqlstring + '				SELECT @error_Code = 3002'													+ CHAR(13)
			select @sqlstring = @sqlstring + '				SELECT @msg = ''No Records Found For The Given Id'''						+ CHAR(13)
			select @sqlstring = @sqlstring + '				GOTO LBL1'																	+ CHAR(13)
			select @sqlstring = @sqlstring + '			END'																			+ CHAR(13)
			select @sqlstring = @sqlstring + '			ELSE'																			+ CHAR(13)
			select @sqlstring = @sqlstring + '			BEGIN'																			+ CHAR(13)
			select @sqlstring = @sqlstring + '				SELECT @error_Code = 3003'													+ CHAR(13)
			select @sqlstring = @sqlstring + '				SELECT @msg = ''Success '' + Convert(varchar,@rowcnt) + '' Records Found'''	+ CHAR(13)
			select @sqlstring = @sqlstring + '				GOTO LBL3'																	+ CHAR(13)
			select @sqlstring = @sqlstring + '			END'																			+ CHAR(13)
			select @sqlstring = @sqlstring + '		END'																				+ CHAR(13)
		end
		select @sqlstring = @sqlstring + '		GOTO LBL3'																				+ CHAR(13)
		select @sqlstring = @sqlstring + '	END'																						+ CHAR(13)
		select @sqlstring = @sqlstring + '	ELSE IF(@ind =''2'')'																		+ CHAR(13)
		select @sqlstring = @sqlstring + '	BEGIN'																						+ CHAR(13)
		select @sqlstring = @sqlstring + @insertnotnullquery
		select @sqlstring = @sqlstring + @insertstring1
		select @sqlstring = @sqlstring + @insertstring2
		select @sqlstring = @sqlstring + '		SELECT @'+ @PrimaryColumnName +'= '+@PrimaryColumnName+''								+ CHAR(13)
		select @sqlstring = @sqlstring + '			FROM '+@TableName+''																+ CHAR(13)
		select @sqlstring = @sqlstring + '			WHERE @@ROWCOUNT > 0 AND @@ERROR = 0 AND '+@PrimaryColumnName+' = scope_identity()'	+ CHAR(13)
		select @sqlstring = @sqlstring + '		IF(@'+@PrimaryColumnName+'>0)'															+ CHAR(13)				
		select @sqlstring = @sqlstring + '		BEGIN'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @new_Id = @'+@PrimaryColumnName+''											+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @error_Code = 3005'															+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @msg = ''Saved Successfully'''												+ CHAR(13)
		select @sqlstring = @sqlstring + '			GOTO LBL3'																			+ CHAR(13)
		select @sqlstring = @sqlstring + '		END'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '		ELSE'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '		BEGIN'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @error_Code = 3004'															+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @msg = ''Insertion Failed'''													+ CHAR(13)
		select @sqlstring = @sqlstring + '			GOTO LBL1'																			+ CHAR(13)
		select @sqlstring = @sqlstring + '		END'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '	END'																						+ CHAR(13)
		select @sqlstring = @sqlstring + '	ELSE IF(@ind =''3'')'																		+ CHAR(13)
		select @sqlstring = @sqlstring + '	BEGIN'																						+ CHAR(13)
		select @sqlstring = @sqlstring + @updatenotnullquery
		select @sqlstring = @sqlstring + @updatestring1
		select @sqlstring = @sqlstring + '		WHERE '																					+ CHAR(13)
		select @sqlstring = @sqlstring + '			('+@PrimaryColumnName+' = @'+@PrimaryColumnName+')'									+ CHAR(13)
		select @sqlstring = @sqlstring + @updatewherestring
		select @sqlstring = @sqlstring + '		IF(@@ROWCOUNT>0 AND @@ERROR = 0)'														+ CHAR(13)
		select @sqlstring = @sqlstring + '		BEGIN'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @error_Code = 3007'															+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @msg = ''Updated Successfully'''												+ CHAR(13)
		select @sqlstring = @sqlstring + '			GOTO LBL3'																			+ CHAR(13)
		select @sqlstring = @sqlstring + '		END'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '		ELSE'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '		BEGIN'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @error_Code = 3006'															+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @msg = ''Updation Failed'''													+ CHAR(13)
		select @sqlstring = @sqlstring + '			GOTO LBL1'																			+ CHAR(13)
		select @sqlstring = @sqlstring + '		END'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '	END'																						+ CHAR(13)
		select @sqlstring = @sqlstring + '	ELSE IF(@ind =''4'')'																		+ CHAR(13)
		select @sqlstring = @sqlstring + '	BEGIN'																						+ CHAR(13)
		select @sqlstring = @sqlstring + '		DELETE '+@TableName+''																	+ CHAR(13)
		select @sqlstring = @sqlstring + '		WHERE ('+@PrimaryColumnName+' = @'+@PrimaryColumnName+') '								+ CHAR(13)
		select @sqlstring = @sqlstring + '		IF(@@ROWCOUNT >0 AND @@ERROR = 0)'														+ CHAR(13)
		select @sqlstring = @sqlstring + '		BEGIN'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @error_Code = 3009'															+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @msg = ''Deleted Successfully'''												+ CHAR(13)
		select @sqlstring = @sqlstring + '			GOTO LBL3'																			+ CHAR(13)
		select @sqlstring = @sqlstring + '		END'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '		ELSE'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '		BEGIN'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @error_Code = 3008'															+ CHAR(13)
		select @sqlstring = @sqlstring + '			SELECT @msg = ''Deletion Failed'''													+ CHAR(13)
		select @sqlstring = @sqlstring + '			GOTO LBL1'																			+ CHAR(13)
		select @sqlstring = @sqlstring + '		END'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '	END'																						+ CHAR(13)
		select @sqlstring = @sqlstring + ''																								+ CHAR(13)
		select @sqlstring = @sqlstring + '	SELECT @error_Code = 3001'																	+ CHAR(13)
		select @sqlstring = @sqlstring + '	GOTO LBL1'																					+ CHAR(13)
		select @sqlstring = @sqlstring + '	LBL3:'																						+ CHAR(13)
		select @sqlstring = @sqlstring + '		IF(@error_Code IS NULL)'																+ CHAR(13)
		select @sqlstring = @sqlstring + '			SET @error_Code = 0'																+ CHAR(13)
		select @sqlstring = @sqlstring + '		IF(@new_Id IS NULL)'																	+ CHAR(13)
		select @sqlstring = @sqlstring + '			SET @new_Id = 0'																	+ CHAR(13)
		select @sqlstring = @sqlstring + '		RETURN 1'																				+ CHAR(13)
		select @sqlstring = @sqlstring + '	LBL1:'																						+ CHAR(13)
		select @sqlstring = @sqlstring + '		IF(@error_Code IS NULL)'																+ CHAR(13)
		select @sqlstring = @sqlstring + '			SET @error_Code = 0'																+ CHAR(13)
		select @sqlstring = @sqlstring + '		IF(@new_Id IS NULL)'																	+ CHAR(13)
		select @sqlstring = @sqlstring + '			SET @new_Id = 0'																	+ CHAR(13)
		select @sqlstring = @sqlstring + '		RETURN 0'																				+ CHAR(13)
		select @sqlstring = @sqlstring + 'END'																							+ CHAR(13)+ CHAR(13)
		select @dropsqlstring 
		print @dropsqlstring
		exec (@dropsqlstring)
		select @sqlstring 
		print @sqlstring
		exec (@sqlstring)
		GOTO LBL3
	END
	LBL3:
		RETURN 1
	LBL1:
		RETURN 0
END

