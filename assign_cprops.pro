pro assign_cprops $
   , kernels = kernel_ind $
   , kernfile = kernfile $
   , idlformat = idlformat $
   , data=data $
   , infile=infile $
   , mask=mask $
   , inmask=inmask $
   , hdr=hdr $
   , sigma=sigma $
   , outfile=outfile $
   , islands=islands $
   , assign=assign $
   , verbose=verbose

  compile_opt idl2

; &%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%
; READ IN THE DATA
; &%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%

  if n_elements(infile) gt 0 then begin
     file_data = file_search(infile, count=file_ct)
     if file_ct eq 0 then begin
        message, "Data not found.", /info
        return
     endif else begin
        data = readfits(file_data, hdr)
     endelse
  endif

  if n_elements(mask) eq 0 then begin
     file_mask = file_search(inmask, count=file_ct)
     if file_ct eq 0 then begin
        message, "Mask not found.", /info
        return
     endif else begin
        mask = readfits(file_mask, mask_hdr)
     endelse
  endif

; &%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%
; READ IN THE KERNELS
; &%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%

  if n_elements(kernfile) gt 0 then begin
     if keyword_set(idlformat) then begin
        restore, kernfile
     endif else begin
        readcol, kernfile, comment="#" $
                 , format="L,L,L,F,F,F,F" $
                 , kern_xpix, kern_ypix, kern_zpix $
                 , kern_ra, kern_dec, kern_vel, kern_int
        xyv_to_ind, x=kern_xpix, y=kern_ypix, v=kern_zpix $
                    , sz=size(data), ind=kernel_ind
     endelse
  endif

; %&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&
; DEFINITIONS AND DEFAULTS
; %&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&

; -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
; GET AN RMS ESTIMATE
; -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

  if n_elements(sigma) eq 0 then $
     sigma = mad(data)

; -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
; SET THE MINIMUM NUMBER OF LEVELS
; -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

  if n_elements(nmin) eq 0 then $
     nmin = 100  

; &%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%
; PARE CUBE TO MINIMUM SIZE
; &%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%
  
; Convert the data inside the mask to a vector

  vectorify, data $
             , mask = mask $
             , x = x, y = y, v = v, t = t $
             , ind = cubeindex

; Rebuild a minimum-sized cube from the vectorized data.

  szdata = size(data)
  cubify, x, y, v, t $
          , cube = minicube $
          , pad = 3 $
          , twod = (szdata[0] eq 2) $
          , indvec = cubeindex $
          , indcube = indcube

  minikern = kernel_ind
  for i = 0, n_elements(minikern)-1 do $
     minikern[i] = where(indcube eq kernel_ind[i])

; %&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&
; ASSIGNMENT
; %&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&

; CALCULATE LEVELS TO WORK WITH
  levels = $
     contour_values( $
     minicube $
     , /linspace $
     , spacing=0.2*sigma $
     , nmin=nmin)

; WORK OUT MERGER MATRIX
  merger_matrix =  $
     mergefind_approx(minicube $
                      , minikern $
                      , levels=levels $
                      , all_neighbors = all_neighbors $
                      , verbose = verbose)     
  merger_matrix_nodiag = merger_matrix
  sz_merge = size(merger_matrix)
  ind = lindgen(sz_merge[1])
  merger_matrix_nodiag[ind,ind] = !values.f_nan

; INITIALIZE ASSIGNMENT CUBE
  sz = size(data)
  assign = lonarr(sz[1], sz[2], sz[3])

; LOOP OVER KERNELS
  counter = 1
  nkern = n_elements(kernel_ind)
  for i = 0, nkern-1 do begin

;    GIVE COUNTER
     if keyword_set(verbose) then begin
        counter, i, nkern, "Merge calculations for "
     endif

;    ... FIND THE CONTOUR WHERE THE KERNEL HAS NOT MERGED
     if total(finite(merger_matrix_nodiag[i,*])) gt 0 then begin
        top_merger = max(merger_matrix_nodiag[i,*],/nan)
        unique_lev = min(levels[where(levels gt top_merger)],/nan)
     endif else begin
        unique_lev = min(levels,/nan)
     endelse

;    ... GET THE CLOUD ASSOCIATED WITH THIS REGION
     reg = label_region(minicube gt unique_lev)
     cloud_ind = where(reg eq reg[minikern[i]])

;     assign[indcube[cloud_ind]] = counter
     assign[indcube[cloud_ind]] = counter
     counter += 1

  endfor
  
; %&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&
; OUTPUT
; %&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&%&

  out_hdr = hdr
  sxaddpar, hdr, "BUNIT", "ASSIGNMENT"
  writefits, outfile, assign, hdr

end
